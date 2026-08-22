#include <stdint.h>
#include <stdlib.h>
#include <opus.h>

void *flashnote_opus_decoder_create(int32_t sample_rate, int32_t channels, int32_t *error) {
    return opus_decoder_create(sample_rate, channels, error);
}

int32_t flashnote_opus_decode(
    void *decoder,
    const uint8_t *packet,
    int32_t packet_length,
    int16_t *output,
    int32_t frame_size
) {
    return opus_decode(decoder, packet, packet_length, output, frame_size, 0);
}

void flashnote_opus_decoder_destroy(void *decoder) {
    opus_decoder_destroy(decoder);
}
