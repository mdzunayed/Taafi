# Notification sounds

> **Superseded:** in-app event sounds now play `assets/audio/bubble.mp3`
> through the shared `NotificationSoundService`
> (`lib/core/audio/notification_sound_service.dart`, exposed as
> `notificationSoundProvider`). Both the notification hub and chat
> providers trigger it on new socket arrivals.
>
> `notification_chime.wav` in this folder is no longer referenced by any
> Dart code — kept only as a spare clip. Safe to delete along with the
> `assets/sounds/` pubspec entry if nothing else adopts it.

Guidelines for any clip that lives here or in `assets/audio/`: keep it
~1 s or shorter and normalised so it doesn't startle users in quiet
rooms. Playback runs through `audioplayers` in `PlayerMode.lowLatency`,
so files should be small enough to sit in memory comfortably (a
17–100 KB mp3 is plenty).
