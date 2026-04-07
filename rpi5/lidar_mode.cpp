/**
 * Utilitaire pour contrôler le Unitree L2 LiDAR via Ethernet UDP.
 *
 * Usage:
 *   ./lidar_mode start       # Démarre la rotation du LiDAR
 *   ./lidar_mode stop        # Arrête la rotation du LiDAR
 *   ./lidar_mode reset       # Reset le LiDAR
 *   ./lidar_mode sync        # Synchronise le timestamp avec le système
 *   ./lidar_mode mode <N>    # Set work mode (uint32)
 */

#include "unitree_lidar_sdk.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <unistd.h>

using namespace unilidar_sdk2;

UnitreeLidarReader* connect_lidar() {
    UnitreeLidarReader* lreader = createUnitreeLidarReader();
    // Port local 6202 pour éviter le conflit avec le driver ROS2 sur 6201
    int ret = lreader->initializeUDP(6101, "192.168.1.62", 6202, "192.168.1.2");
    if (ret != 0) {
        printf("Erreur: impossible de se connecter au LiDAR (%d)\n", ret);
        return nullptr;
    }
    return lreader;
}

void usage(const char* prog) {
    printf("Usage: %s <start|stop|reset|sync|mode N>\n", prog);
    printf("  start  — Démarre la rotation\n");
    printf("  stop   — Arrête la rotation\n");
    printf("  reset  — Reset le LiDAR\n");
    printf("  sync   — Synchronise le timestamp\n");
    printf("  mode N — Set work mode (uint32)\n");
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        usage(argv[0]);
        return 1;
    }

    const char* cmd = argv[1];

    // Validate command
    if (strcmp(cmd, "start") != 0 && strcmp(cmd, "stop") != 0 &&
        strcmp(cmd, "reset") != 0 && strcmp(cmd, "sync") != 0 &&
        strcmp(cmd, "mode") != 0) {
        usage(argv[0]);
        return 1;
    }

    if (strcmp(cmd, "mode") == 0 && argc < 3) {
        printf("Erreur: 'mode' nécessite un argument numérique\n");
        return 1;
    }

    UnitreeLidarReader* lreader = connect_lidar();
    if (!lreader) return 2;

    if (strcmp(cmd, "start") == 0) {
        printf("LiDAR → START\n");
        lreader->startLidarRotation();
    } else if (strcmp(cmd, "stop") == 0) {
        printf("LiDAR → STOP\n");
        lreader->stopLidarRotation();
    } else if (strcmp(cmd, "reset") == 0) {
        printf("LiDAR → RESET\n");
        lreader->resetLidar();
    } else if (strcmp(cmd, "sync") == 0) {
        printf("LiDAR → SYNC TIMESTAMP\n");
        lreader->syncLidarTimeStamp();
    } else if (strcmp(cmd, "mode") == 0) {
        uint32_t mode = (uint32_t)atoi(argv[2]);
        printf("LiDAR → MODE %u\n", mode);
        lreader->setLidarWorkMode(mode);
    }

    usleep(500000);
    lreader->closeUDP();
    return 0;
}
