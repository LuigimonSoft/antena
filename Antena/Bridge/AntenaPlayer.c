// SPDX-License-Identifier: GPL-2.0-only
#include "AntenaPlayer.h"
#include <vlc/vlc.h>
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#define CAPACITY (188u * 32768u)
struct AntenaPlayer {
    libvlc_instance_t *instance;
    libvlc_media_player_t *player;
    libvlc_media_t *media;
    pthread_mutex_t mutex;
    pthread_cond_t ready;
    unsigned char *buffer;
    size_t head, count;
    uint64_t received, dropped;
    bool ended;
};
static int open_input(void *opaque, void **data, uint64_t *size) {
    *data = opaque; *size = UINT64_MAX; return 0;
}
static ssize_t read_input(void *opaque, unsigned char *buffer, size_t size) {
    AntenaPlayer *p = opaque;
    pthread_mutex_lock(&p->mutex);
    while (!p->count && !p->ended) pthread_cond_wait(&p->ready, &p->mutex);
    size_t n = size < p->count ? size : p->count;
    size_t first = CAPACITY - p->head;
    if (first > n) first = n;
    memcpy(buffer, p->buffer + p->head, first);
    memcpy(buffer + first, p->buffer, n - first);
    p->head = (p->head + n) % CAPACITY; p->count -= n;
    pthread_mutex_unlock(&p->mutex);
    return (ssize_t)n;
}
static void close_input(void *opaque) { (void)opaque; }
AntenaPlayer *ant_player_create(const char *runtimePath) {
    char path[4096];
    snprintf(path, sizeof path, "%s/plugins", runtimePath); setenv("VLC_PLUGIN_PATH", path, 1);
    snprintf(path, sizeof path, "%s/share", runtimePath); setenv("VLC_DATA_PATH", path, 1);
    const char *args[] = {"--no-video-title-show", "--no-osd", "--no-snapshot-preview",
        "--vout=macosx", "--quiet"};
    AntenaPlayer *p = calloc(1, sizeof *p);
    if (!p) return NULL;
    p->buffer = malloc(CAPACITY);
    if (!p->buffer) { free(p); return NULL; }
    pthread_mutex_init(&p->mutex, NULL); pthread_cond_init(&p->ready, NULL);
    p->ended = true;
    p->instance = libvlc_new(sizeof args / sizeof args[0], args);
    if (p->instance) p->player = libvlc_media_player_new(p->instance);
    if (!p->player) { ant_player_destroy(p); return NULL; }
    return p;
}
void ant_player_set_view(AntenaPlayer *p, void *view) { libvlc_media_player_set_nsobject(p->player, view); }
void ant_player_end_input(AntenaPlayer *p) {
    pthread_mutex_lock(&p->mutex); p->ended = true;
    pthread_cond_broadcast(&p->ready); pthread_mutex_unlock(&p->mutex);
}
void ant_player_stop(AntenaPlayer *p) {
    ant_player_end_input(p);
    if (p->player) libvlc_media_player_stop(p->player);
    if (p->media) { libvlc_media_release(p->media); p->media = NULL; }
}
int ant_player_live(AntenaPlayer *p) {
    ant_player_stop(p);
    pthread_mutex_lock(&p->mutex);
    p->head = p->count = 0; p->received = p->dropped = 0; p->ended = false;
    pthread_mutex_unlock(&p->mutex);
    p->media = libvlc_media_new_callbacks(p->instance, open_input, read_input, NULL, close_input, p);
    if (!p->media) return -1;
    libvlc_media_add_option(p->media, ":demux=ts");
    libvlc_media_add_option(p->media, ":live-caching=450");
    libvlc_media_add_option(p->media, ":clock-jitter=0");
    libvlc_media_add_option(p->media, ":sub-language=eng,fra");
    libvlc_media_player_set_media(p->player, p->media);
    return libvlc_media_player_play(p->player);
}
int ant_player_file(AntenaPlayer *p, const char *path) {
    ant_player_stop(p);
    p->media = libvlc_media_new_path(p->instance, path);
    if (!p->media) return -1;
    libvlc_media_player_set_media(p->player, p->media);
    return libvlc_media_player_play(p->player);
}
void ant_player_feed(AntenaPlayer *p, const void *data, size_t size) {
    const unsigned char *bytes = data;
    pthread_mutex_lock(&p->mutex);
    if (p->ended) { pthread_mutex_unlock(&p->mutex); return; }
    p->received += size;
    if (size > CAPACITY) { p->dropped += size - CAPACITY; bytes += size - CAPACITY; size = CAPACITY; }
    if (size > CAPACITY - p->count) {
        size_t discard = size - (CAPACITY - p->count);
        p->head = (p->head + discard) % CAPACITY; p->count -= discard; p->dropped += discard;
    }
    size_t tail = (p->head + p->count) % CAPACITY, first = CAPACITY - tail;
    if (first > size) first = size;
    memcpy(p->buffer + tail, bytes, first); memcpy(p->buffer, bytes + first, size - first);
    p->count += size; pthread_cond_signal(&p->ready); pthread_mutex_unlock(&p->mutex);
}
void ant_player_destroy(AntenaPlayer *p) {
    if (!p) return;
    ant_player_stop(p);
    if (p->player) libvlc_media_player_release(p->player);
    if (p->instance) libvlc_release(p->instance);
    pthread_cond_destroy(&p->ready); pthread_mutex_destroy(&p->mutex);
    free(p->buffer); free(p);
}
void ant_player_volume(AntenaPlayer *p, int volume) { libvlc_audio_set_volume(p->player, volume); }
int ant_player_subtitles(AntenaPlayer *p, AntenaTrack *tracks, int capacity) {
    libvlc_track_description_t *head = libvlc_video_get_spu_description(p->player);
    int count = 0;
    for (libvlc_track_description_t *t = head; t && count < capacity; t = t->p_next) {
        if (t->i_id < 0) continue;
        tracks[count].id = t->i_id;
        snprintf(tracks[count].name, sizeof tracks[count].name, "%s", t->psz_name ? t->psz_name : "CC"); ++count;
    }
    libvlc_track_description_list_release(head); return count;
}
int ant_player_set_subtitle(AntenaPlayer *p, int id) { return libvlc_video_set_spu(p->player, id); }
AntenaPlayerStats ant_player_stats(AntenaPlayer *p) {
    AntenaPlayerStats s = {0};
    s.state = libvlc_media_player_get_state(p->player);
    libvlc_video_get_size(p->player, 0, &s.width, &s.height);
    if (p->media) {
        libvlc_media_stats_t stats = {0};
        if (libvlc_media_get_stats(p->media, &stats)) {
            s.decodedVideo = stats.i_decoded_video; s.displayedVideo = stats.i_displayed_pictures;
            s.decodedAudio = stats.i_decoded_audio; s.playedAudio = stats.i_played_abuffers;
            s.lostVideo = stats.i_lost_pictures;
        }
    }
    pthread_mutex_lock(&p->mutex); s.receivedBytes = p->received; s.droppedBytes = p->dropped;
    pthread_mutex_unlock(&p->mutex); return s;
}
