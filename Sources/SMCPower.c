#include "SMCPower.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <math.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#ifdef POWERBAR_SMC_PROBE
#include <stdio.h>
#define PB_DEBUG(...) fprintf(stderr, __VA_ARGS__)
#else
#define PB_DEBUG(...) ((void)0)
#endif

// SMC user-client wire layout. Only key metadata (9) and value reads (5)
// are implemented here. There is intentionally no write operation.
typedef struct {
    uint32_t key;
    uint8_t version[6];
    uint8_t pad0[2];
    uint8_t limits[16];
    uint32_t size;
    uint32_t type;
    uint8_t attributes;
    uint8_t pad1[3];
    uint8_t result;
    uint8_t status;
    uint8_t command;
    uint8_t pad2;
    uint32_t index;
    uint8_t bytes[32];
} PBPacket;
_Static_assert(sizeof(PBPacket) == 80, "SMC packet size");
_Static_assert(offsetof(PBPacket, bytes) == 48, "SMC value offset");

typedef struct { uint32_t key, size, type; int checked; } PBKey;
static io_connect_t connection = IO_OBJECT_NULL;
static int attempted = 0;
static PBKey input_key = {0x50445452, 0, 0, 0}; // PDTR: DC input watts
static PBKey system_key = {0x50535452, 0, 0, 0}; // PSTR: system-total watts

static int open_connection(void) {
    if (connection) return 1;
    if (attempted) return 0;
    attempted = 1;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"));
    if (!service) { PB_DEBUG("SMC service not found\n"); return 0; }
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 1, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) { PB_DEBUG("SMC open: 0x%x\n", result); connection = IO_OBJECT_NULL; return 0; }
    return 1;
}

static int read_packet(PBKey *key, uint8_t command, PBPacket *reply) {
    PBPacket request = {0};
    request.key = key->key;
    request.size = key->size;
    request.command = command;
    size_t length = sizeof(*reply);
    kern_return_t result = IOConnectCallStructMethod(connection, 2, &request, sizeof(request), reply, &length);
    PB_DEBUG("SMC command %u key %08x: kernel 0x%x result %u length %zu size %u type %08x\n", command, key->key, result, reply->result, length, reply->size, reply->type);
    return result == KERN_SUCCESS && length == sizeof(*reply) && reply->result == 0;
}

static double read_watts(PBKey *key) {
    if (!open_connection()) return NAN;
    // Open/close the user client's read transaction, leaving its connection cached.
    kern_return_t result = IOConnectCallMethod(connection, 0, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL);
    if (result != KERN_SUCCESS) { PB_DEBUG("SMC transaction open: 0x%x\n", result); return NAN; }
    PBPacket reply = {0};
    double value = NAN;
    if (!key->checked) {
        key->checked = 1;
        if (read_packet(key, 9, &reply)) { key->size = reply.size; key->type = reply.type; }
    }
    if (key->size > 0 && key->size <= 32 && read_packet(key, 5, &reply)) {
        if (key->type == 0x666c7420 && key->size == 4) { // flt : native IEEE float
            float watts;
            memcpy(&watts, reply.bytes, sizeof(watts));
            value = watts;
        } else if (key->size == 2 && (key->type >> 16) == 0x7370) { // signed fixed point spXY
            unsigned char fraction = (unsigned char)key->type;
            int bits = fraction >= '0' && fraction <= '9' ? fraction - '0' :
                fraction >= 'a' && fraction <= 'f' ? fraction - 'a' + 10 : -1;
            if (bits >= 0) {
                int16_t raw = (int16_t)(((uint16_t)reply.bytes[0] << 8) | reply.bytes[1]);
                value = ldexp((double)raw, -bits);
            }
        }
    }
    IOConnectCallMethod(connection, 1, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL);
    return isfinite(value) && value >= 0 && value <= 500 ? value : NAN;
}

double powerbar_smc_input(void) { return read_watts(&input_key); }
double powerbar_smc_system(void) { return read_watts(&system_key); }
void powerbar_smc_close(void) {
    if (connection) IOServiceClose(connection);
    connection = IO_OBJECT_NULL;
    attempted = 0;
    input_key.checked = system_key.checked = 0;
}

#ifdef POWERBAR_SMC_PROBE
#include <stdio.h>
#include <unistd.h>
int main(void) {
    for (int i = 0; i < 7; i++) {
        printf("Live charger: %.3f W | Live system: %.3f W\n", powerbar_smc_input(), powerbar_smc_system());
        fflush(stdout);
        if (i < 6) sleep(2);
    }
    powerbar_smc_close();
}
#endif
