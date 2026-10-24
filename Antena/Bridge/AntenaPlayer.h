// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
typedef struct AntenaPlayer AntenaPlayer;
typedef struct { int id; char name[160]; } AntenaTrack;
typedef struct {
    int state, decodedVideo, displayedVideo, decodedAudio, playedAudio, lostVideo;
    unsigned width, height;
    uint64_t receivedBytes, droppedBytes;
} AntenaPlayerStats;
AntenaPlayer *ant_player_create(const char *runtimePath);
void ant_player_set_view(AntenaPlayer *player, void *view);
int ant_player_live(AntenaPlayer *player);
int ant_player_file(AntenaPlayer *player, const char *path);
void ant_player_feed(AntenaPlayer *player, const void *data, size_t size);
void ant_player_end_input(AntenaPlayer *player);
void ant_player_stop(AntenaPlayer *player);
void ant_player_destroy(AntenaPlayer *player);
void ant_player_volume(AntenaPlayer *player, int volume);
int ant_player_subtitles(AntenaPlayer *player, AntenaTrack *tracks, int capacity);
int ant_player_set_subtitle(AntenaPlayer *player, int id);
AntenaPlayerStats ant_player_stats(AntenaPlayer *player);
