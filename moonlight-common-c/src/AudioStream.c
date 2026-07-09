#include "Limelight-internal.h"

static SOCKET rtpSocket = INVALID_SOCKET;

static LINKED_BLOCKING_QUEUE packetQueue;
static RTP_AUDIO_QUEUE rtpAudioQueue;

static PLT_THREAD udpPingThread;
static PLT_THREAD receiveThread;
static PLT_THREAD decoderThread;

static PPLT_CRYPTO_CONTEXT audioDecryptionCtx;
static uint32_t avRiKeyId;

static unsigned short lastSeq;

static bool pingThreadStarted;
static bool receivedDataFromPeer;
static uint64_t firstReceiveTime;
static uint64_t audioStreamStartTime;
static uint32_t audioPacketsReceived;
static uint32_t audioDataPacketsReceived;
static uint32_t audioFecPacketsReceived;
static uint32_t audioPacketsSubmitted;
static uint32_t audioResyncPacketsDropped;
static uint32_t audioRuntPackets;
static uint32_t audioQueueOverflows;
static uint32_t audioDecryptFailures;
static uint32_t audioPlcRequests;

#ifdef LC_DEBUG
#define INVALID_OPUS_HEADER 0x00
static uint8_t opusHeaderByte;
#endif

#define MAX_PACKET_SIZE 1400

typedef struct _QUEUE_AUDIO_PACKET_HEADER {
    LINKED_BLOCKING_QUEUE_ENTRY lentry;
    int size;
} QUEUED_AUDIO_PACKET_HEADER, *PQUEUED_AUDIO_PACKET_HEADER;

typedef struct _QUEUED_AUDIO_PACKET {
    QUEUED_AUDIO_PACKET_HEADER header;
    char data[MAX_PACKET_SIZE];
} QUEUED_AUDIO_PACKET, *PQUEUED_AUDIO_PACKET;

static void AudioPingThreadProc(void* context) {
    char legacyPingData[] = { 0x50, 0x49, 0x4E, 0x47 };
    LC_SOCKADDR saddr;

    LC_ASSERT(AudioPortNumber != 0);

    memcpy(&saddr, &RemoteAddr, sizeof(saddr));
    SET_PORT(&saddr, AudioPortNumber);

    // We do not check for errors here. Socket errors will be handled
    // on the read-side in ReceiveThreadProc(). This avoids potential
    // issues related to receiving ICMP port unreachable messages due
    // to sending a packet prior to the host PC binding to that port.
    int pingCount = 0;
    while (!PltIsThreadInterrupted(&udpPingThread)) {
        if (AudioPingPayload.payload[0] != 0) {
            pingCount++;
            AudioPingPayload.sequenceNumber = BE32(pingCount);

            sendto(rtpSocket, (char*)&AudioPingPayload, sizeof(AudioPingPayload), 0, (struct sockaddr*)&saddr, AddrLen);
        }
        else {
            sendto(rtpSocket, legacyPingData, sizeof(legacyPingData), 0, (struct sockaddr*)&saddr, AddrLen);
        }

        PltSleepMsInterruptible(&udpPingThread, 500);
    }
}

// Initialize the audio stream and start
int initializeAudioStream(void) {
    LbqInitializeLinkedBlockingQueue(&packetQueue, 30);
    RtpaInitializeQueue(&rtpAudioQueue);
    lastSeq = 0;
    receivedDataFromPeer = false;
    pingThreadStarted = false;
    firstReceiveTime = 0;
    audioStreamStartTime = PltGetMillis();
    audioPacketsReceived = 0;
    audioDataPacketsReceived = 0;
    audioFecPacketsReceived = 0;
    audioPacketsSubmitted = 0;
    audioResyncPacketsDropped = 0;
    audioRuntPackets = 0;
    audioQueueOverflows = 0;
    audioDecryptFailures = 0;
    audioPlcRequests = 0;
    audioDecryptionCtx = PltCreateCryptoContext();
#ifdef LC_DEBUG
    opusHeaderByte = INVALID_OPUS_HEADER;
#endif

    // Copy and byte-swap the AV RI key ID used for the audio encryption IV
    memcpy(&avRiKeyId, StreamConfig.remoteInputAesIv, sizeof(avRiKeyId));
    avRiKeyId = BE32(avRiKeyId);

    Limelog("Audio stream initialized: audioConfig=0x%x, encryptionFlags=0x%x, arCaps=0x%x\n",
            StreamConfig.audioConfiguration, StreamConfig.encryptionFlags, AudioCallbacks.capabilities);

    return 0;
}

// This is called when the RTSP SETUP message is parsed and the audio port
// number is parsed out of it. Alternatively, it's also called if parsing fails
// and will use the well known audio port instead.
int notifyAudioPortNegotiationComplete(void) {
    LC_ASSERT(!pingThreadStarted);
    LC_ASSERT(AudioPortNumber != 0);

    Limelog("Audio port negotiation complete: audioPort=%u, addressFamily=%d\n",
            AudioPortNumber, RemoteAddr.ss_family);

    // For GFE 3.22 compatibility, we must start the audio ping thread before the RTSP handshake.
    // It will not reply to our RTSP PLAY request until the audio ping has been received.
    rtpSocket = bindUdpSocket(RemoteAddr.ss_family, &LocalAddr, AddrLen, 0, SOCK_QOS_TYPE_AUDIO);
    if (rtpSocket == INVALID_SOCKET) {
        Limelog("Audio UDP socket bind failed: error=%d\n", (int)LastSocketError());
        return LastSocketFail();
    }
    Limelog("Audio UDP socket bound; starting ping thread\n");

    // We may receive audio before our threads are started, but that's okay. We'll
    // drop the first 1 second of audio packets to catch up with the backlog.
    int err = PltCreateThread("AudioPing", AudioPingThreadProc, NULL, &udpPingThread);
    if (err != 0) {
        Limelog("Audio ping thread creation failed: %d\n", err);
        return err;
    }

    pingThreadStarted = true;
    Limelog("Audio ping thread started\n");
    return 0;
}

static void freePacketList(PLINKED_BLOCKING_QUEUE_ENTRY entry) {
    PLINKED_BLOCKING_QUEUE_ENTRY nextEntry;

    while (entry != NULL) {
        nextEntry = entry->flink;

        // The entry is stored within the data allocation
        free(entry->data);

        entry = nextEntry;
    }
}

// Tear down the audio stream once we're done with it
void destroyAudioStream(void) {
    Limelog("Destroying audio stream: socketOpen=%d, pingThreadStarted=%d\n",
            rtpSocket != INVALID_SOCKET, pingThreadStarted);

    if (rtpSocket != INVALID_SOCKET) {
        if (pingThreadStarted) {
            PltInterruptThread(&udpPingThread);
            PltJoinThread(&udpPingThread);
            Limelog("Audio ping thread stopped\n");
        }

        closeSocket(rtpSocket);
        rtpSocket = INVALID_SOCKET;
    }

    PltDestroyCryptoContext(audioDecryptionCtx);
    freePacketList(LbqDestroyLinkedBlockingQueue(&packetQueue));
    RtpaCleanupQueue(&rtpAudioQueue);
    Limelog("Audio stream destroyed\n");
}

static bool queuePacketToLbq(PQUEUED_AUDIO_PACKET* packet) {
    int err;

    do {
        err = LbqOfferQueueItem(&packetQueue, *packet, &(*packet)->header.lentry);
        if (err == LBQ_SUCCESS) {
            // The LBQ owns the buffer now
            *packet = NULL;
        }
        else if (err == LBQ_BOUND_EXCEEDED) {
            audioQueueOverflows++;
            Limelog("Audio packet queue overflow: overflows=%u, queuedFrames=%d\n",
                    audioQueueOverflows, LiGetPendingAudioFrames());

            // The audio queue is full, so free all existing items and try again
            freePacketList(LbqFlushQueueItems(&packetQueue));
        }
    } while (err == LBQ_BOUND_EXCEEDED);

    return err == LBQ_SUCCESS;
}

static void decodeInputData(PQUEUED_AUDIO_PACKET packet) {
    // If the packet size is zero, this is a placeholder for a missing
    // packet. Trigger packet loss concealment logic in libopus by
    // invoking the decoder with a NULL buffer.
    if (packet->header.size == 0) {
        audioPlcRequests++;
        audioPacketsSubmitted++;
        AudioCallbacks.decodeAndPlaySample(NULL, 0);
        return;
    }

    PRTP_PACKET rtp = (PRTP_PACKET)&packet->data[0];
    if (lastSeq != 0 && (unsigned short)(lastSeq + 1) != rtp->sequenceNumber) {
        Limelog("Network dropped audio data (expected %d, but received %d)\n", lastSeq + 1, rtp->sequenceNumber);
    }

    lastSeq = rtp->sequenceNumber;

    if (AudioEncryptionEnabled) {
        // We must have room for the AES padding which may be written to the buffer
        unsigned char decryptedOpusData[ROUND_TO_PKCS7_PADDED_LEN(MAX_PACKET_SIZE)];
        unsigned char iv[16] = { 0 };
        int dataLength = packet->header.size - sizeof(*rtp);

        LC_ASSERT(dataLength <= MAX_PACKET_SIZE);

        // The IV is the avkeyid (equivalent to the rikeyid) +
        // the RTP sequence number, in big endian.
        uint32_t ivSeq = BE32(avRiKeyId + rtp->sequenceNumber);

        memcpy(iv, &ivSeq, sizeof(ivSeq));

        if (!PltDecryptMessage(audioDecryptionCtx, ALGORITHM_AES_CBC, CIPHER_FLAG_RESET_IV | CIPHER_FLAG_FINISH,
                               (unsigned char*)StreamConfig.remoteInputAesKey, sizeof(StreamConfig.remoteInputAesKey),
                               iv, sizeof(iv),
                               NULL, 0,
                               (unsigned char*)(rtp + 1), dataLength,
                               decryptedOpusData, &dataLength)) {
            audioDecryptFailures++;
            Limelog("Failed to decrypt audio packet (sequence number: %u, failures=%u)\n",
                    rtp->sequenceNumber, audioDecryptFailures);
            LC_ASSERT_VT(false);
            return;
        }

#ifdef LC_DEBUG
        if (opusHeaderByte == INVALID_OPUS_HEADER) {
            opusHeaderByte = decryptedOpusData[0];
            LC_ASSERT_VT(opusHeaderByte != INVALID_OPUS_HEADER);
        }
        else {
            // Opus header should stay constant for the entire stream.
            // If it doesn't, it may indicate that the RtpAudioQueue
            // incorrectly recovered a data shard or the decryption
            // of the audio packet failed. Sunshine violates this for
            // surround sound in some cases, so just ignore it.
            LC_ASSERT_VT(decryptedOpusData[0] == opusHeaderByte || IS_SUNSHINE());
        }
#endif

        audioPacketsSubmitted++;
        AudioCallbacks.decodeAndPlaySample((char*)decryptedOpusData, dataLength);
    }
    else {
#ifdef LC_DEBUG
        if (opusHeaderByte == INVALID_OPUS_HEADER) {
            opusHeaderByte = ((uint8_t*)(rtp + 1))[0];
            LC_ASSERT_VT(opusHeaderByte != INVALID_OPUS_HEADER);
        }
        else {
            // Opus header should stay constant for the entire stream.
            // If it doesn't, it may indicate that the RtpAudioQueue
            // incorrectly recovered a data shard. Sunshine violates
            // this for surround sound in some cases, so just ignore it.
            LC_ASSERT_VT(((uint8_t*)(rtp + 1))[0] == opusHeaderByte || IS_SUNSHINE());
        }
#endif

        audioPacketsSubmitted++;
        AudioCallbacks.decodeAndPlaySample((char*)(rtp + 1), packet->header.size - sizeof(*rtp));
    }
}

static void AudioReceiveThreadProc(void* context) {
    PRTP_PACKET rtp;
    PQUEUED_AUDIO_PACKET packet;
    int queueStatus;
    bool useSelect;
    uint32_t packetsToDrop;
    int waitingForAudioMs;
    int nextAudioWaitLogMs;

    packet = NULL;
    packetsToDrop = 500 / AudioPacketDuration;
    nextAudioWaitLogMs = 1000;

    if (setNonFatalRecvTimeoutMs(rtpSocket, UDP_RECV_POLL_TIMEOUT_MS) < 0) {
        // SO_RCVTIMEO failed, so use select() to wait
        useSelect = true;
    }
    else {
        // SO_RCVTIMEO timeout set for recv()
        useSelect = false;
    }

    Limelog("Audio receive thread started: packetSize=%d, audioPacketDuration=%d, initialDropMs=%d, useSelect=%d, encrypted=%d\n",
            MAX_PACKET_SIZE, AudioPacketDuration, packetsToDrop * AudioPacketDuration,
            useSelect, AudioEncryptionEnabled);

    waitingForAudioMs = 0;
    while (!PltIsThreadInterrupted(&receiveThread)) {
        if (packet == NULL) {
            packet = (PQUEUED_AUDIO_PACKET)malloc(sizeof(*packet));
            if (packet == NULL) {
                Limelog("Audio Receive: malloc() failed\n");
                ListenerCallbacks.connectionTerminated(-1);
                break;
            }
        }

        packet->header.size = recvUdpSocket(rtpSocket, &packet->data[0], MAX_PACKET_SIZE, useSelect);
        if (packet->header.size < 0) {
            Limelog("Audio Receive: recvUdpSocket() failed: %d\n", (int)LastSocketError());
            ListenerCallbacks.connectionTerminated(LastSocketFail());
            break;
        }
        else if (packet->header.size == 0) {
            // Receive timed out; try again
            
            if (!receivedDataFromPeer) {
                waitingForAudioMs += UDP_RECV_POLL_TIMEOUT_MS;
                if (waitingForAudioMs >= nextAudioWaitLogMs) {
                    Limelog("Still waiting for first audio packet after %d ms (audioPort=%u)\n",
                            waitingForAudioMs, AudioPortNumber);
                    nextAudioWaitLogMs += 1000;
                }
            }
            else {
                // If we hit this path, there are no queued audio packets on the host PC,
                // so we don't need to drop anything.
                packetsToDrop = 0;
            }
            continue;
        }

        if (packet->header.size < (int)sizeof(RTP_PACKET)) {
            // Runt packet
            audioRuntPackets++;
            if (audioRuntPackets <= 3 || (audioRuntPackets % 100) == 0) {
                Limelog("Discarding runt audio packet: size=%d, runts=%u\n",
                        packet->header.size, audioRuntPackets);
            }
            continue;
        }

        rtp = (PRTP_PACKET)&packet->data[0];
        audioPacketsReceived++;
        if (rtp->packetType == 97) {
            audioDataPacketsReceived++;
        }
        else {
            audioFecPacketsReceived++;
        }

        if (!receivedDataFromPeer) {
            receivedDataFromPeer = true;
            Limelog("Received first audio packet after %d ms (size=%d, type=%u, seq=%u, timestamp=%u)\n",
                    waitingForAudioMs, packet->header.size, rtp->packetType,
                    BE16(rtp->sequenceNumber), BE32(rtp->timestamp));

            if (firstReceiveTime != 0) {
                // XXX firstReceiveTime is never set here...
                // We're already dropping 500ms of audio so this probably doesn't matter
                packetsToDrop += (uint32_t)(PltGetMillis() - firstReceiveTime) / AudioPacketDuration;
            }

            Limelog("Initial audio resync period: %d milliseconds\n", packetsToDrop * AudioPacketDuration);
        }

        // GFE accumulates audio samples before we are ready to receive them, so
        // we will drop the ones that arrived before the receive thread was ready.
        if (packetsToDrop > 0) {
            // Only count actual audio data (not FEC) in the packets to drop calculation
            if (rtp->packetType == 97) {
                audioResyncPacketsDropped++;
                packetsToDrop--;
                if (audioResyncPacketsDropped <= 3 || packetsToDrop == 0) {
                    Limelog("Dropping startup audio packet for resync: dropped=%u, remainingDropMs=%u\n",
                            audioResyncPacketsDropped, packetsToDrop * AudioPacketDuration);
                }
            }
            continue;
        }

        // Convert fields to host byte-order
        rtp->sequenceNumber = BE16(rtp->sequenceNumber);
        rtp->timestamp = BE32(rtp->timestamp);
        rtp->ssrc = BE32(rtp->ssrc);

        queueStatus = RtpaAddPacket(&rtpAudioQueue, (PRTP_PACKET)&packet->data[0], (uint16_t)packet->header.size);
        if (RTPQ_HANDLE_NOW(queueStatus)) {
            if ((AudioCallbacks.capabilities & CAPABILITY_DIRECT_SUBMIT) == 0) {
                if (!queuePacketToLbq(&packet)) {
                    // An exit signal was received
                    break;
                }
                else {
                    // Ownership should have been taken by the LBQ
                    LC_ASSERT(packet == NULL);
                }
            }
            else {
                decodeInputData(packet);
            }
        }
        else {
            if (RTPQ_PACKET_CONSUMED(queueStatus)) {
                // The queue consumed our packet, so we must allocate a new one
                packet = NULL;
            }

            if (RTPQ_PACKET_READY(queueStatus)) {
                // If packets are ready, pull them and send them to the decoder
                uint16_t length;
                PQUEUED_AUDIO_PACKET queuedPacket;
                while ((queuedPacket = (PQUEUED_AUDIO_PACKET)RtpaGetQueuedPacket(&rtpAudioQueue, sizeof(QUEUED_AUDIO_PACKET_HEADER), &length)) != NULL) {
                    // Populate header data (not preserved in queued packets)
                    queuedPacket->header.size = length;

                    if ((AudioCallbacks.capabilities & CAPABILITY_DIRECT_SUBMIT) == 0) {
                        if (!queuePacketToLbq(&queuedPacket)) {
                            // An exit signal was received
                            free(queuedPacket);
                            break;
                        }
                        else {
                            // Ownership should have been taken by the LBQ
                            LC_ASSERT(queuedPacket == NULL);
                        }
                    }
                    else {
                        decodeInputData(queuedPacket);
                        free(queuedPacket);
                    }
                }
                
                // Break on exit
                if (queuedPacket != NULL) {
                    break;
                }
            }
        }
    }
    
    if (packet != NULL) {
        free(packet);
    }

    Limelog("Audio receive thread exiting: received=%u, data=%u, fec=%u, submitted=%u, startupDrops=%u, runts=%u, decryptFailures=%u, plcRequests=%u\n",
            audioPacketsReceived, audioDataPacketsReceived, audioFecPacketsReceived,
            audioPacketsSubmitted, audioResyncPacketsDropped, audioRuntPackets,
            audioDecryptFailures, audioPlcRequests);
}

static void AudioDecoderThreadProc(void* context) {
    int err;
    PQUEUED_AUDIO_PACKET packet;

    while (!PltIsThreadInterrupted(&decoderThread)) {
        err = LbqWaitForQueueElement(&packetQueue, (void**)&packet);
        if (err != LBQ_SUCCESS) {
            // An exit signal was received
            return;
        }

        decodeInputData(packet);

        free(packet);
    }
}

void stopAudioStream(void) {
    Limelog("Stopping audio stream: received=%u, submitted=%u, startupDrops=%u, overflows=%u, pendingFrames=%d, pendingDurationMs=%d\n",
            audioPacketsReceived, audioPacketsSubmitted, audioResyncPacketsDropped,
            audioQueueOverflows, LiGetPendingAudioFrames(), LiGetPendingAudioDuration());

    if (!receivedDataFromPeer) {
        Limelog("No audio traffic was ever received from the host!\n");
    }

    AudioCallbacks.stop();

    PltInterruptThread(&receiveThread);
    if ((AudioCallbacks.capabilities & CAPABILITY_DIRECT_SUBMIT) == 0) {        
        // Signal threads waiting on the LBQ
        LbqSignalQueueShutdown(&packetQueue);
        PltInterruptThread(&decoderThread);
    }
    
    PltJoinThread(&receiveThread);
    if ((AudioCallbacks.capabilities & CAPABILITY_DIRECT_SUBMIT) == 0) {
        PltJoinThread(&decoderThread);
    }

    AudioCallbacks.cleanup();
    Limelog("Audio stream stopped: lifetimeMs=%llu, received=%u, data=%u, fec=%u, submitted=%u, startupDrops=%u, runts=%u, overflows=%u, decryptFailures=%u, plcRequests=%u\n",
            (unsigned long long)(PltGetMillis() - audioStreamStartTime),
            audioPacketsReceived, audioDataPacketsReceived, audioFecPacketsReceived,
            audioPacketsSubmitted, audioResyncPacketsDropped, audioRuntPackets,
            audioQueueOverflows, audioDecryptFailures, audioPlcRequests);
}

int startAudioStream(void* audioContext, int arFlags) {
    int err;
    OPUS_MULTISTREAM_CONFIGURATION chosenConfig;

    if (HighQualitySurroundEnabled) {
        LC_ASSERT(HighQualitySurroundSupported);
        LC_ASSERT(HighQualityOpusConfig.channelCount != 0);
        LC_ASSERT(HighQualityOpusConfig.streams != 0);
        chosenConfig = HighQualityOpusConfig;
    }
    else {
        LC_ASSERT(NormalQualityOpusConfig.channelCount != 0);
        LC_ASSERT(NormalQualityOpusConfig.streams != 0);
        chosenConfig = NormalQualityOpusConfig;
    }

    chosenConfig.samplesPerFrame = 48 * AudioPacketDuration;
    Limelog("Starting audio stream: audioPacketDuration=%d, sampleRate=%d, channels=%d, streams=%d, coupledStreams=%d, samplesPerFrame=%d, arFlags=0x%x, directSubmit=%d\n",
            AudioPacketDuration, chosenConfig.sampleRate, chosenConfig.channelCount,
            chosenConfig.streams, chosenConfig.coupledStreams, chosenConfig.samplesPerFrame,
            arFlags, (AudioCallbacks.capabilities & CAPABILITY_DIRECT_SUBMIT) != 0);

    err = AudioCallbacks.init(StreamConfig.audioConfiguration, &chosenConfig, audioContext, arFlags);
    if (err != 0) {
        Limelog("Audio renderer init failed: %d\n", err);
        return err;
    }
    Limelog("Audio renderer init complete\n");

    AudioCallbacks.start();
    Limelog("Audio renderer start callback complete\n");

    err = PltCreateThread("AudioRecv", AudioReceiveThreadProc, NULL, &receiveThread);
    if (err != 0) {
        Limelog("Audio receive thread creation failed: %d\n", err);
        AudioCallbacks.stop();
        closeSocket(rtpSocket);
        AudioCallbacks.cleanup();
        return err;
    }
    Limelog("Audio receive thread created\n");

    if ((AudioCallbacks.capabilities & CAPABILITY_DIRECT_SUBMIT) == 0) {
        err = PltCreateThread("AudioDec", AudioDecoderThreadProc, NULL, &decoderThread);
        if (err != 0) {
            Limelog("Audio decoder thread creation failed: %d\n", err);
            AudioCallbacks.stop();
            PltInterruptThread(&receiveThread);
            PltJoinThread(&receiveThread);
            closeSocket(rtpSocket);
            AudioCallbacks.cleanup();
            return err;
        }
        Limelog("Audio decoder thread created\n");
    }

    Limelog("Audio stream started\n");
    return 0;
}

int LiGetPendingAudioFrames(void) {
    return LbqGetItemCount(&packetQueue);
}

int LiGetPendingAudioDuration(void) {
    return LiGetPendingAudioFrames() * AudioPacketDuration;
}
