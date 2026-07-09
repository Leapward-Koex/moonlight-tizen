#include "Limelight-internal.h"

#define FIRST_FRAME_MAX 1500
#define FIRST_FRAME_TIMEOUT_SEC 10

#define FIRST_FRAME_PORT 47996

static RTP_VIDEO_QUEUE rtpQueue;

static SOCKET rtpSocket = INVALID_SOCKET;
static SOCKET firstFrameSocket = INVALID_SOCKET;

static PPLT_CRYPTO_CONTEXT decryptionCtx;

static PLT_THREAD udpPingThread;
static PLT_THREAD receiveThread;
static PLT_THREAD decoderThread;

static bool receivedDataFromPeer;
static uint64_t firstDataTimeMs;
static bool receivedFullFrame;
static uint64_t videoStreamStartTimeMs;
static uint32_t videoPacketsReceived;
static uint32_t videoRuntPackets;
static uint32_t videoDecryptFailures;

// We can't request an IDR frame until the depacketizer knows
// that a packet was lost. This timeout bounds the time that
// the RTP queue will wait for missing/reordered packets.
#define RTP_QUEUE_DELAY 10

// This is the desired number of video packets that can be
// stored in the socket's receive buffer. 2048 is chosen
// because it should be large enough for all reasonable
// frame sizes (probably 2 or 3 frames) without using too
// much kernel memory with larger packet sizes. It also
// can smooth over transient pauses in network traffic
// and subsequent packet/frame bursts that follow.
#define RTP_RECV_PACKETS_BUFFERED 2048

// Initialize the video stream
void initializeVideoStream(void) {
    initializeVideoDepacketizer(StreamConfig.packetSize);
    RtpvInitializeQueue(&rtpQueue);
    decryptionCtx = PltCreateCryptoContext();
    receivedDataFromPeer = false;
    firstDataTimeMs = 0;
    receivedFullFrame = false;
    videoStreamStartTimeMs = PltGetMillis();
    videoPacketsReceived = 0;
    videoRuntPackets = 0;
    videoDecryptFailures = 0;
    Limelog("Video stream initialized: packetSize=%d, fps=%d, supportedFormats=0x%x, encryptionFlags=0x%x\n",
            StreamConfig.packetSize, StreamConfig.fps, StreamConfig.supportedVideoFormats,
            StreamConfig.encryptionFlags);
}

// Clean up the video stream
void destroyVideoStream(void) {
    Limelog("Destroying video stream: received=%u, runts=%u, decryptFailures=%u, receivedFullFrame=%d\n",
            videoPacketsReceived, videoRuntPackets, videoDecryptFailures, receivedFullFrame);
    PltDestroyCryptoContext(decryptionCtx);
    destroyVideoDepacketizer();
    RtpvCleanupQueue(&rtpQueue);
    Limelog("Video stream destroyed\n");
}

// UDP Ping proc
static void VideoPingThreadProc(void* context) {
    char legacyPingData[] = { 0x50, 0x49, 0x4E, 0x47 };
    LC_SOCKADDR saddr;

    LC_ASSERT(VideoPortNumber != 0);

    memcpy(&saddr, &RemoteAddr, sizeof(saddr));
    SET_PORT(&saddr, VideoPortNumber);

    // We do not check for errors here. Socket errors will be handled
    // on the read-side in ReceiveThreadProc(). This avoids potential
    // issues related to receiving ICMP port unreachable messages due
    // to sending a packet prior to the host PC binding to that port.
    int pingCount = 0;
    while (!PltIsThreadInterrupted(&udpPingThread)) {
        if (VideoPingPayload.payload[0] != 0) {
            pingCount++;
            VideoPingPayload.sequenceNumber = BE32(pingCount);

            sendto(rtpSocket, (char*)&VideoPingPayload, sizeof(VideoPingPayload), 0, (struct sockaddr*)&saddr, AddrLen);
        }
        else {
            sendto(rtpSocket, legacyPingData, sizeof(legacyPingData), 0, (struct sockaddr*)&saddr, AddrLen);
        }

        PltSleepMsInterruptible(&udpPingThread, 500);
    }
}

// Receive thread proc
static void VideoReceiveThreadProc(void* context) {
    int err;
    int bufferSize, receiveSize, decryptedSize, minSize;
    char* buffer;
    char* encryptedBuffer;
    int queueStatus;
    bool useSelect;
    int waitingForVideoMs;
    int nextVideoWaitLogMs;
    bool encrypted;

    encrypted = !!(EncryptionFeaturesEnabled & SS_ENC_VIDEO);
    decryptedSize = StreamConfig.packetSize + MAX_RTP_HEADER_SIZE;
    minSize = sizeof(RTP_PACKET) + ((EncryptionFeaturesEnabled & SS_ENC_VIDEO) ? sizeof(ENC_VIDEO_HEADER) : 0);
    receiveSize = decryptedSize + ((EncryptionFeaturesEnabled & SS_ENC_VIDEO) ? sizeof(ENC_VIDEO_HEADER) : 0);
    bufferSize = decryptedSize + sizeof(RTPV_QUEUE_ENTRY);
    buffer = NULL;

    if (setNonFatalRecvTimeoutMs(rtpSocket, UDP_RECV_POLL_TIMEOUT_MS) < 0) {
        // SO_RCVTIMEO failed, so use select() to wait
        useSelect = true;
    }
    else {
        // SO_RCVTIMEO timeout set for recv()
        useSelect = false;
    }

    Limelog("Video receive thread started: encrypted=%d, packetSize=%d, receiveSize=%d, minSize=%d, useSelect=%d, videoPort=%u\n",
            encrypted, StreamConfig.packetSize, receiveSize, minSize, useSelect, VideoPortNumber);

    // Allocate a staging buffer to use for each received packet
    if (encrypted) {
        encryptedBuffer = (char*)malloc(receiveSize);
        if (encryptedBuffer == NULL) {
            Limelog("Video Receive: malloc() failed\n");
            ListenerCallbacks.connectionTerminated(-1);
            return;
        }
    }
    else {
        encryptedBuffer = NULL;
    }

    waitingForVideoMs = 0;
    nextVideoWaitLogMs = 1000;
    while (!PltIsThreadInterrupted(&receiveThread)) {
        PRTP_PACKET packet;

        if (buffer == NULL) {
            buffer = (char*)malloc(bufferSize);
            if (buffer == NULL) {
                Limelog("Video Receive: malloc() failed\n");
                ListenerCallbacks.connectionTerminated(-1);
                break;
            }
        }

        err = recvUdpSocket(rtpSocket,
                            encrypted ? encryptedBuffer : buffer,
                            receiveSize,
                            useSelect);
        if (err < 0) {
            Limelog("Video Receive: recvUdpSocket() failed: %d\n", (int)LastSocketError());
            ListenerCallbacks.connectionTerminated(LastSocketFail());
            break;
        }
        else if  (err == 0) {
            if (!receivedDataFromPeer) {
                // If we wait many seconds without ever receiving a video packet,
                // assume something is broken and terminate the connection.
                waitingForVideoMs += UDP_RECV_POLL_TIMEOUT_MS;
                if (waitingForVideoMs >= nextVideoWaitLogMs) {
                    Limelog("Still waiting for first video packet after %d ms (videoPort=%u)\n",
                            waitingForVideoMs, VideoPortNumber);
                    nextVideoWaitLogMs += 1000;
                }
                if (waitingForVideoMs >= FIRST_FRAME_TIMEOUT_SEC * 1000) {
                    Limelog("Terminating connection due to lack of video traffic\n");
                    ListenerCallbacks.connectionTerminated(ML_ERROR_NO_VIDEO_TRAFFIC);
                    break;
                }
            }
            
            // Receive timed out; try again
            continue;
        }

        if (!receivedDataFromPeer) {
            receivedDataFromPeer = true;
            Limelog("Received first video packet after %d ms (size=%d, encrypted=%d)\n",
                    waitingForVideoMs, err, encrypted);

            firstDataTimeMs = PltGetMillis();
        }

#ifndef LC_FUZZING
        if (!receivedFullFrame) {
            uint64_t now = PltGetMillis();

            if (now - firstDataTimeMs >= FIRST_FRAME_TIMEOUT_SEC * 1000) {
                Limelog("Terminating connection due to lack of a successful video frame\n");
                ListenerCallbacks.connectionTerminated(ML_ERROR_NO_VIDEO_FRAME);
                break;
            }
        }
#endif

        if (err < minSize) {
            // Runt packet
            videoRuntPackets++;
            if (videoRuntPackets <= 3 || (videoRuntPackets % 100) == 0) {
                Limelog("Discarding runt video packet: size=%d, minSize=%d, runts=%u\n",
                        err, minSize, videoRuntPackets);
            }
            continue;
        }

        // Decrypt the packet into the buffer if encryption is enabled
        if (encrypted) {
            PENC_VIDEO_HEADER encHeader = (PENC_VIDEO_HEADER)encryptedBuffer;

            // If this frame is below our current frame number, discard it before decryption
            // to save CPU cycles decrypting FEC shards for a frame we already reassembled.
            //
            // Since this is happening _before_ decryption, this packet is not trusted yet.
            // It's imperative that we do not mutate any state based on this packet until
            // after it has been decrypted successfully!
            //
            // It's possible for an attacker to inject a fake packet that has any value of
            // header fields they want, however this provides them no benefit because we will
            // simply drop said packet here (if it's below the current frame number) or it
            // will pass this check and be dropped during decryption (if contents is tampered)
            // or after decryption in the RTP queue (if it's a replay of a previous authentic
            // packet from the host).
            //
            // In short, an attacker spoofing this value via MITM or sending malicious values
            // impersonating the host from off-link doesn't gain them anything. If they have
            // a true MITM, they can DoS our connection by just dropping all our traffic, so
            // tampering with packets to fail this check doesn't accomplish anything they
            // couldn't already do. If they're not on-link, we just throw their malicious
            // traffic away (as mentioned in the paragraph above) and continue accepting
            // legitmate video traffic.
            if (encHeader->frameNumber && LE32(encHeader->frameNumber) < RtpvGetCurrentFrameNumber(&rtpQueue)) {
                continue;
            }

            if (!PltDecryptMessage(decryptionCtx, ALGORITHM_AES_GCM, 0,
                                   (unsigned char*)StreamConfig.remoteInputAesKey, sizeof(StreamConfig.remoteInputAesKey),
                                   encHeader->iv, sizeof(encHeader->iv),
                                   encHeader->tag, sizeof(encHeader->tag),
                                   ((unsigned char*)(encHeader + 1)), err - sizeof(ENC_VIDEO_HEADER), // The ciphertext is after the header
                                   (unsigned char*)buffer, &err)) {
                videoDecryptFailures++;
                Limelog("Failed to decrypt video packet: failures=%u\n", videoDecryptFailures);
                continue;
            }
        }

        // Convert fields to host byte-order
        packet = (PRTP_PACKET)&buffer[0];
        packet->sequenceNumber = BE16(packet->sequenceNumber);
        packet->timestamp = BE32(packet->timestamp);
        packet->ssrc = BE32(packet->ssrc);
        videoPacketsReceived++;
        if (videoPacketsReceived == 1) {
            Limelog("First parsed video RTP packet: seq=%u, timestamp=%u, ssrc=%u\n",
                    packet->sequenceNumber, packet->timestamp, packet->ssrc);
        }

        queueStatus = RtpvAddPacket(&rtpQueue, packet, err, (PRTPV_QUEUE_ENTRY)&buffer[decryptedSize]);

        if (queueStatus == RTPF_RET_QUEUED) {
            // The queue owns the buffer
            buffer = NULL;
        }
    }

    if (buffer != NULL) {
        free(buffer);
    }

    if (encryptedBuffer != NULL) {
        free(encryptedBuffer);
    }

    Limelog("Video receive thread exiting: received=%u, runts=%u, decryptFailures=%u, receivedFullFrame=%d\n",
            videoPacketsReceived, videoRuntPackets, videoDecryptFailures, receivedFullFrame);
}

void notifyKeyFrameReceived(void) {
    if (!receivedFullFrame) {
        Limelog("Received first complete video key frame after %llu ms from first packet (streamLifetimeMs=%llu)\n",
                (unsigned long long)(firstDataTimeMs ? PltGetMillis() - firstDataTimeMs : 0),
                (unsigned long long)(PltGetMillis() - videoStreamStartTimeMs));
    }

    // Remember that we got a full frame successfully
    receivedFullFrame = true;
}

// Decoder thread proc
static void VideoDecoderThreadProc(void* context) {
    while (!PltIsThreadInterrupted(&decoderThread)) {
        VIDEO_FRAME_HANDLE frameHandle;
        PDECODE_UNIT decodeUnit;

        if (!LiWaitForNextVideoFrame(&frameHandle, &decodeUnit)) {
            return;
        }

        LiCompleteVideoFrame(frameHandle, VideoCallbacks.submitDecodeUnit(decodeUnit));
    }
}

// Read the first frame of the video stream
int readFirstFrame(void) {
    // All that matters is that we close this socket.
    // This starts the flow of video on Gen 3 servers.

    closeSocket(firstFrameSocket);
    firstFrameSocket = INVALID_SOCKET;

    return 0;
}

// Terminate the video stream
void stopVideoStream(void) {
    Limelog("Stopping video stream: received=%u, runts=%u, decryptFailures=%u, receivedFullFrame=%d\n",
            videoPacketsReceived, videoRuntPackets, videoDecryptFailures, receivedFullFrame);

    if (!receivedDataFromPeer) {
        Limelog("No video traffic was ever received from the host!\n");
    }

    VideoCallbacks.stop();

    // Wake up client code that may be waiting on the decode unit queue
    stopVideoDepacketizer();
    
    PltInterruptThread(&udpPingThread);
    PltInterruptThread(&receiveThread);
    if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
        PltInterruptThread(&decoderThread);
    }

    if (firstFrameSocket != INVALID_SOCKET) {
        shutdownTcpSocket(firstFrameSocket);
    }

    PltJoinThread(&udpPingThread);
    PltJoinThread(&receiveThread);
    if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
        PltJoinThread(&decoderThread);
    }
    
    if (firstFrameSocket != INVALID_SOCKET) {
        closeSocket(firstFrameSocket);
        firstFrameSocket = INVALID_SOCKET;
    }
    if (rtpSocket != INVALID_SOCKET) {
        closeSocket(rtpSocket);
        rtpSocket = INVALID_SOCKET;
    }

    VideoCallbacks.cleanup();
    Limelog("Video stream stopped: lifetimeMs=%llu, received=%u, runts=%u, decryptFailures=%u, receivedFullFrame=%d\n",
            (unsigned long long)(PltGetMillis() - videoStreamStartTimeMs),
            videoPacketsReceived, videoRuntPackets, videoDecryptFailures, receivedFullFrame);
}

// Start the video stream
int startVideoStream(void* rendererContext, int drFlags) {
    int err;

    firstFrameSocket = INVALID_SOCKET;
    Limelog("Starting video stream: negotiatedFormat=0x%x, width=%d, height=%d, fps=%d, packetSize=%d, drFlags=0x%x, drCaps=0x%x, appMajor=%d\n",
            NegotiatedVideoFormat, StreamConfig.width, StreamConfig.height, StreamConfig.fps,
            StreamConfig.packetSize, drFlags, VideoCallbacks.capabilities, AppVersionQuad[0]);

    // This must be called before the decoder thread starts submitting
    // decode units
    LC_ASSERT(NegotiatedVideoFormat != 0);
    err = VideoCallbacks.setup(NegotiatedVideoFormat, StreamConfig.width,
        StreamConfig.height, StreamConfig.fps, rendererContext, drFlags);
    if (err != 0) {
        Limelog("Video renderer setup failed: %d\n", err);
        return err;
    }
    Limelog("Video renderer setup complete\n");

    rtpSocket = bindUdpSocket(RemoteAddr.ss_family, &LocalAddr, AddrLen,
                              RTP_RECV_PACKETS_BUFFERED * (StreamConfig.packetSize + MAX_RTP_HEADER_SIZE),
                              SOCK_QOS_TYPE_VIDEO);
    if (rtpSocket == INVALID_SOCKET) {
        Limelog("Video UDP socket bind failed: error=%d\n", (int)LastSocketError());
        VideoCallbacks.cleanup();
        return LastSocketError();
    }
    Limelog("Video UDP socket bound: receiveBufferBytes=%d, videoPort=%u\n",
            RTP_RECV_PACKETS_BUFFERED * (StreamConfig.packetSize + MAX_RTP_HEADER_SIZE),
            VideoPortNumber);

    VideoCallbacks.start();
    Limelog("Video renderer start callback complete\n");

    err = PltCreateThread("VideoRecv", VideoReceiveThreadProc, NULL, &receiveThread);
    if (err != 0) {
        Limelog("Video receive thread creation failed: %d\n", err);
        VideoCallbacks.stop();
        closeSocket(rtpSocket);
        VideoCallbacks.cleanup();
        return err;
    }
    Limelog("Video receive thread created\n");

    if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
        err = PltCreateThread("VideoDec", VideoDecoderThreadProc, NULL, &decoderThread);
        if (err != 0) {
            Limelog("Video decoder thread creation failed: %d\n", err);
            VideoCallbacks.stop();
            PltInterruptThread(&receiveThread);
            PltJoinThread(&receiveThread);
            closeSocket(rtpSocket);
            VideoCallbacks.cleanup();
            return err;
        }
        Limelog("Video decoder thread created\n");
    }

    if (AppVersionQuad[0] == 3) {
        // Connect this socket to open port 47998 for our ping thread
        firstFrameSocket = connectTcpSocket(&RemoteAddr, AddrLen,
                                            FIRST_FRAME_PORT, FIRST_FRAME_TIMEOUT_SEC);
        if (firstFrameSocket == INVALID_SOCKET) {
            Limelog("Video first-frame TCP socket connection failed: port=%u, error=%d\n",
                    FIRST_FRAME_PORT, (int)LastSocketError());
            VideoCallbacks.stop();
            stopVideoDepacketizer();
            PltInterruptThread(&receiveThread);
            if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
                PltInterruptThread(&decoderThread);
            }
            PltJoinThread(&receiveThread);
            if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
                PltJoinThread(&decoderThread);
            }
            closeSocket(rtpSocket);
            VideoCallbacks.cleanup();
            return LastSocketError();
        }
        Limelog("Video first-frame TCP socket connected: port=%u\n", FIRST_FRAME_PORT);
    }

    // Start pinging before reading the first frame so GFE knows where
    // to send UDP data
    err = PltCreateThread("VideoPing", VideoPingThreadProc, NULL, &udpPingThread);
    if (err != 0) {
        Limelog("Video ping thread creation failed: %d\n", err);
        VideoCallbacks.stop();
        stopVideoDepacketizer();
        PltInterruptThread(&receiveThread);
        if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
            PltInterruptThread(&decoderThread);
        }
        PltJoinThread(&receiveThread);
        if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
            PltJoinThread(&decoderThread);
        }
        closeSocket(rtpSocket);
        if (firstFrameSocket != INVALID_SOCKET) {
            closeSocket(firstFrameSocket);
            firstFrameSocket = INVALID_SOCKET;
        }
        VideoCallbacks.cleanup();
        return err;
    }
    Limelog("Video ping thread created\n");

    if (AppVersionQuad[0] == 3) {
        // Read the first frame to start the flow of video
        err = readFirstFrame();
        if (err != 0) {
            Limelog("Video readFirstFrame failed: %d\n", err);
            stopVideoStream();
            return err;
        }
        Limelog("Video readFirstFrame complete\n");
    }

    Limelog("Video stream started\n");
    return 0;
}
