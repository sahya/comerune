package com.example.comerune.speech.infrastructure.player

/**
 * Issue #927: shared so production [MediaPlayerWavPlayer] / [AudioTrackWavPlayer]
 * and the test [FakeWavPlayer] reference one constant. Renaming it now changes
 * production and the fake together, making silent test-vs-production drift
 * impossible.
 *
 * Message text intentionally unchanged from the previous hardcoded literal.
 */
internal const val PLAYER_RELEASED_MESSAGE = "Player has been released"
