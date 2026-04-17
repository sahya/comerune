package app.spectacles_software.comerune.speech.domain.settings

import app.spectacles_software.comerune.speech.domain.model.SpeechSettings

class InMemorySettingsRepository : SettingsRepository {
    private var settings: SpeechSettings = SpeechSettings()

    @Synchronized
    override fun get(): SpeechSettings = settings

    @Synchronized
    override fun save(settings: SpeechSettings) {
        this.settings = settings
    }
}
