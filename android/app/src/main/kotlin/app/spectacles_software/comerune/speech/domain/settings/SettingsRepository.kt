package app.spectacles_software.comerune.speech.domain.settings

import app.spectacles_software.comerune.speech.domain.model.SpeechSettings

interface SettingsRepository {
    fun get(): SpeechSettings
    fun save(settings: SpeechSettings)
}
