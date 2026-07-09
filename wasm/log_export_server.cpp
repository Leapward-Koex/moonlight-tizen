#include "moonlight_wasm.hpp"

#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>

namespace {

constexpr int kExportTimeoutSeconds = 600;
constexpr int kRequestBufferSize = 8192;

std::atomic<bool> g_LogExportRunning(false);
std::atomic<int> g_LogExportListenFd(-1);
std::mutex g_LogExportMutex;
std::thread g_LogExportThread;
std::string g_LogExportPayload;
std::string g_LogExportToken;
std::string g_LogExportFilename;
int g_LogExportPort = 0;

std::string LastSocketError(const std::string& context) {
  int errorCode = errno;
  std::ostringstream message;
  message << context << " (" << errorCode << ": " << std::strerror(errorCode) << ")";
  return message.str();
}

void CloseListenSocket() {
  int fd = g_LogExportListenFd.exchange(-1);
  if (fd >= 0) {
    shutdown(fd, SHUT_RDWR);
    close(fd);
  }
}

bool SendAll(int fd, const std::string& data) {
  const char* cursor = data.data();
  size_t remaining = data.size();
  while (remaining > 0) {
    ssize_t sent = send(fd, cursor, remaining, 0);
    if (sent <= 0) {
      return false;
    }
    cursor += sent;
    remaining -= static_cast<size_t>(sent);
  }
  return true;
}

std::string SanitizeFilename(const std::string& filename) {
  std::string sanitized;
  sanitized.reserve(filename.size());
  for (char ch : filename) {
    if (ch == '"' || ch == '\\' || ch == '/' || ch == '\r' || ch == '\n') {
      sanitized.push_back('_');
    } else {
      sanitized.push_back(ch);
    }
  }
  if (sanitized.empty()) {
    return "moonlight-log.ndjson";
  }
  return sanitized;
}

std::string HttpStatus(int status, const std::string& reason, const std::string& body) {
  std::ostringstream response;
  response << "HTTP/1.1 " << status << " " << reason << "\r\n"
           << "Connection: close\r\n"
           << "Content-Type: text/plain; charset=utf-8\r\n"
           << "Content-Length: " << body.size() << "\r\n"
           << "Cache-Control: no-store\r\n"
           << "Access-Control-Allow-Origin: *\r\n"
           << "\r\n"
           << body;
  return response.str();
}

bool RequestHasValidToken(const std::string& request) {
  size_t lineEnd = request.find("\r\n");
  std::string requestLine = request.substr(0, lineEnd == std::string::npos ? request.size() : lineEnd);
  if (requestLine.find("GET /moonlight-log") != 0) {
    return false;
  }

  std::string tokenNeedle = "token=" + g_LogExportToken;
  return !g_LogExportToken.empty() && requestLine.find(tokenNeedle) != std::string::npos;
}

bool HandleClient(int clientFd) {
  char buffer[kRequestBufferSize];
  ssize_t received = recv(clientFd, buffer, sizeof(buffer) - 1, 0);
  if (received <= 0) {
    return false;
  }
  buffer[received] = '\0';
  std::string request(buffer, static_cast<size_t>(received));

  if (!RequestHasValidToken(request)) {
    SendAll(clientFd, HttpStatus(403, "Forbidden", "Invalid or expired Moonlight log export token.\n"));
    return false;
  }

  std::string filename = SanitizeFilename(g_LogExportFilename);
  std::ostringstream header;
  header << "HTTP/1.1 200 OK\r\n"
         << "Connection: close\r\n"
         << "Content-Type: application/x-ndjson; charset=utf-8\r\n"
         << "Content-Disposition: attachment; filename=\"" << filename << "\"\r\n"
         << "Content-Length: " << g_LogExportPayload.size() << "\r\n"
         << "Cache-Control: no-store\r\n"
         << "Access-Control-Allow-Origin: *\r\n"
         << "\r\n";

  if (!SendAll(clientFd, header.str())) {
    return false;
  }
  return SendAll(clientFd, g_LogExportPayload);
}

void ExportThreadMain() {
  auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(kExportTimeoutSeconds);

  while (g_LogExportRunning.load() && std::chrono::steady_clock::now() < deadline) {
    int listenFd = g_LogExportListenFd.load();
    if (listenFd < 0) {
      break;
    }

    fd_set readSet;
    FD_ZERO(&readSet);
    FD_SET(listenFd, &readSet);
    timeval timeout;
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;

    int ready = select(listenFd + 1, &readSet, nullptr, nullptr, &timeout);
    if (ready <= 0 || !FD_ISSET(listenFd, &readSet)) {
      continue;
    }

    sockaddr_in clientAddress;
    socklen_t clientAddressLength = sizeof(clientAddress);
    int clientFd = accept(listenFd, reinterpret_cast<sockaddr*>(&clientAddress), &clientAddressLength);
    if (clientFd < 0) {
      continue;
    }

    bool downloaded = HandleClient(clientFd);
    shutdown(clientFd, SHUT_RDWR);
    close(clientFd);
    if (downloaded) {
      break;
    }
  }

  g_LogExportRunning.store(false);
  CloseListenSocket();
}

void StopLogExportServerInternal() {
  g_LogExportRunning.store(false);
  CloseListenSocket();
  if (g_LogExportThread.joinable()) {
    g_LogExportThread.join();
  }
  g_LogExportPayload.clear();
  g_LogExportToken.clear();
  g_LogExportFilename.clear();
  g_LogExportPort = 0;
}

} // namespace

MessageResult startLogExportServer(std::string payload, std::string filename, std::string token, int requestedPort) {
  std::lock_guard<std::mutex> lock(g_LogExportMutex);
  StopLogExportServerInternal();

  if (payload.empty()) {
    return MessageResult::Reject(emscripten::val(std::string("No log content is available to export.")));
  }
  if (token.empty()) {
    return MessageResult::Reject(emscripten::val(std::string("A download token is required.")));
  }

  int listenFd = socket(AF_INET, SOCK_STREAM, 0);
  if (listenFd < 0) {
    return MessageResult::Reject(emscripten::val(LastSocketError("Unable to create export socket")));
  }

  int reuse = 1;
  setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

  sockaddr_in address;
  std::memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_ANY);
  address.sin_port = htons(requestedPort > 0 ? requestedPort : 0);

  if (bind(listenFd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
    std::string error = LastSocketError("Unable to bind export socket");
    close(listenFd);
    return MessageResult::Reject(emscripten::val(error));
  }

  if (listen(listenFd, 2) != 0) {
    std::string error = LastSocketError("Unable to listen on export socket");
    close(listenFd);
    return MessageResult::Reject(emscripten::val(error));
  }

  socklen_t addressLength = sizeof(address);
  if (getsockname(listenFd, reinterpret_cast<sockaddr*>(&address), &addressLength) != 0) {
    std::string error = LastSocketError("Unable to read export socket port");
    close(listenFd);
    return MessageResult::Reject(emscripten::val(error));
  }

  g_LogExportPayload = payload;
  g_LogExportToken = token;
  g_LogExportFilename = SanitizeFilename(filename);
  g_LogExportPort = ntohs(address.sin_port);
  g_LogExportListenFd.store(listenFd);
  g_LogExportRunning.store(true);
  g_LogExportThread = std::thread(ExportThreadMain);

  emscripten::val ret = emscripten::val::object();
  ret.set("port", emscripten::val(g_LogExportPort));
  ret.set("path", emscripten::val(std::string("/moonlight-log?token=") + token));
  ret.set("filename", emscripten::val(g_LogExportFilename));
  ret.set("expiresSeconds", emscripten::val(kExportTimeoutSeconds));
  return MessageResult::Resolve(ret);
}

MessageResult stopLogExportServer() {
  std::lock_guard<std::mutex> lock(g_LogExportMutex);
  StopLogExportServerInternal();
  return MessageResult::Resolve();
}

EMSCRIPTEN_BINDINGS(log_export_server) {
  emscripten::function("startLogExportServer", &startLogExportServer);
  emscripten::function("stopLogExportServer", &stopLogExportServer);
}
