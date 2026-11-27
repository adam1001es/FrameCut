# FrameCut – Video-Editor fürs iPhone (ohne Qualitätsverlust)

## Auf dein iPhone bringen (ca. 5 Minuten)

1. **Xcode 16 oder neuer** auf dem Mac (kostenlos im App Store). Auf dem iPhone muss **iOS 17+** laufen.
2. Repo klonen (oder als ZIP laden) und **`FrameCut.xcodeproj`** doppelklicken.
3. Links auf das blaue **FrameCut**-Projekt klicken → Target **FrameCut** → Tab **Signing & Capabilities**:
   - **Team**: deine Apple-ID auswählen (über „Add Account…“, eine kostenlose Apple-ID reicht).
   - **Bundle Identifier**: `com.deinname.framecut` in etwas Eigenes ändern, z. B. `com.max123.framecut`.
4. iPhone per Kabel anschließen, oben in der Leiste als Ziel auswählen und auf **▶︎ (Run)** klicken.
5. Beim ersten Mal auf dem iPhone:
   - **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** einschalten (iPhone startet neu).
   - **Einstellungen → Allgemein → VPN & Geräteverwaltung** → deinem Entwickler-Zertifikat vertrauen.

> Mit einer kostenlosen Apple-ID läuft die App 7 Tage, danach einfach nochmal auf ▶︎ drücken.
> Mit dem bezahlten Developer-Account (99 €/Jahr) läuft sie 1 Jahr.

Xcode 15 oder älter? Dann `brew install xcodegen` und im Ordner `xcodegen` ausführen. Das erzeugt das Projekt neu.

## Funktionen

| Bereich | Was geht |
|---|---|
| Import | Mehrere Videos aus Fotos oder Dateien, **als Original-Datei** (kein Umwandeln durch iOS: 4K, 60 fps, HDR/Dolby Vision, ProRes) |
| Timeline | Playhead fix in der Mitte wie bei CapCut, ziehen = scrubben, zwei Finger = zoomen, Vorschaubilder |
| Schnitt | Am Playhead schneiden (Split), Trimmen, Duplizieren, Reihenfolge ändern, Löschen, Rückgängig/Wiederholen |
| Tempo | 0,25× bis 4× mit Tonhöhenkorrektur |
| Ton | Lautstärke und Stummschalten pro Clip, Musikspur mit Startpunkt, Loop und Ausblenden |
| Look | 12 Filter + Belichtung, Helligkeit, Kontrast, Sättigung, Wärme, Schärfe, Vignette, auch auf alle Clips anwendbar |
| Text | Mehrere Texte, Farbe, Größe, fett, Hintergrund-Box, Position, Start und Dauer |
| Format | Original, 9:16, 16:9, 1:1, 4:5 |
| Export | Verlustfrei 1:1 · ProRes 422 · HEVC höchste Qualität (HDR) · H.264, immer in voller Auflösung, direkt in Fotos |

## So funktioniert „kein Qualitätsverlust“

- **Verlustfrei (1:1)**: Hast du nur geschnitten oder getrimmt, werden die Originaldaten unverändert zusammengesetzt.
  Es wird nichts neu kodiert, das Ergebnis ist Bit für Bit Originalqualität.
- Mit **Effekten** (Filter, Text, Tempo, Musik, Format) muss jedes Bild neu berechnet werden. Dann exportiert die App:
  - **ProRes 422**: Studio-Codec, visuell verlustfrei (auf iPhones mit ProRes-Unterstützung).
  - **HEVC höchste Qualität**: volle Auflösung, HDR bleibt als HLG erhalten.
- Die Ausgabe-Auflösung entspricht immer deinem Material. Nichts wird verkleinert.
  (Hochskalieren über das Original hinaus bringt keine echten Details, deshalb gibt es das nicht.)

## Web-Version

`web/index.html` ist FrameCut als Web-App. Sie läuft in jedem modernen Browser (iPhone, iPad, Mac, PC): einfach die Datei öffnen oder z. B. über GitHub Pages hosten. Die Videos bleiben auf dem Gerät. Der Export wird mit sehr hoher Bitrate neu kodiert, verlustfrei 1:1 geht nur in der iPhone-App.

## Code-Überblick

- `Engine/CompositionBuilder.swift`: baut aus dem Projekt eine AVFoundation-Komposition (Passthrough oder Core-Image-Rendering)
- `Engine/Rendering.swift`: Filter, Text-Rendering in Originalauflösung, Thumbnails
- `Engine/Exporter.swift`: Export-Presets und Speichern in Fotos
- `Model/EditorModel.swift`: Projektzustand, Vorschau-Player, Undo/Redo, Schnittfunktionen
- `Views/`: SwiftUI-Oberfläche (Timeline, Werkzeugleiste, Sheets)
- `web/index.html`: Web-Version (eine Datei, WebGL-Filter, MediaRecorder-Export)
