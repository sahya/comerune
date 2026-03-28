package com.example.comerune.speech.domain.settings

import com.example.comerune.speech.domain.model.SpeechSettings

interface SettingsRepository {
    fun get(): SpeechSettings
    fun save(settings: SpeechSettings)
}
