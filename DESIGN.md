---
version: 1
name: LimitChecker
description: |
  Detailfenster einer macOS-Menüleisten-App. Native Systemschrift, Abschnitte
  direkt auf dem Glas mit Trennlinien wie in Apples WLAN-Menü, jeder Dienst mit
  seinem Original-App-Icon und seiner Markenfarbe, Rot und Orange als Signal.
  Hell und dunkel ohne eigene Varianten, bis auf die Abdunklung des Glases im
  dunklen Modus.

tokens: Sources/LimitChecker/LimitCheckerApp.swift → enum Theme

colors:
  separator: "primary 12 %"          # Trennlinie zwischen Abschnitten
  dark-glass-shade: "black 30 %"     # nur dunkel: Glas so tief wie Apples Menüs
  bar-track: "primary 10 %"          # leere Balkenspur
  gridline: "secondary 25 %"         # Diagrammraster
  secondary-text: "primary 72 %"     # sekundärer Text, gemessen ≥ 5,6 : 1
  warning: "systemOrange"            # Warnsymbole – nie Text, nie Balken
  critical: "systemRed"              # Balken ≤ 20 %
  claude: "#D97757"                  # aus dem Claude-Icon: Balken, Verlauf (Endmarke Kreis)
  codex: "#647AF8"                   # aus der Codex-Wolke: Balken, Verlauf (Endmarke Quadrat)

typography:   # macOS-Textstile, gemessen
  headline: 13 pt fett       # Fenstertitel
  body-semibold: 13 pt       # Dienstname
  title3-semibold: 15 pt     # Prozentwert, Ziffern gleich breit
  callout: 12 pt             # Bezeichnungen, Reset-Zeit, Hinweise, Fließtext
  subheadline: 11 pt         # Achsen, Status

spacing: { section-inset: 16, section-padding: 12, row-gap: 12, bar: 6 }
radius: { bar: Kapsel }
width: 400
hit-target: 24
icon: 28
---

# LimitChecker – Designsystem

Diese Datei hält fest, **wie das Detailfenster aussieht und warum**. Wer etwas an
der Oberfläche ändert (Mensch oder KI-Agent), liest zuerst diese Datei. Die
Werte stehen im Code in `enum Theme`; diese Datei ist ihre Begründung, nicht ihr
Ersatz. Der Menüleisten-Eintrag selbst ist bewusst nicht Teil dieses Systems und
bleibt, wie er ist.

## 1. Grundhaltung

- **Ein Blick genügt.** Die Frage ist immer dieselbe: Wie viel ist noch frei, und
  wann wird zurückgesetzt? Der Prozentwert ist das Größte im Fenster, die
  Reset-Zeit steht direkt darunter und ist ohne Mühe lesbar. Alles andere tritt
  zurück.
- **Nativ statt eigen.** Systemschrift, Systemfarben und Systemsteuerelemente.
  Das Fenster soll neben Kontrollzentrum und WLAN-Menü nicht auffallen.
- **Farbe hat eine Bedeutung: welcher Dienst, oder Achtung.** Jeder Dienst
  erscheint mit seinem echten App-Icon und trägt dessen Markenfarbe in Balken und
  Verlauf: Claude Orange, Codex das Indigo der Wolke. Rot übernimmt, wenn ein
  Balken knapp wird. Eine reine Graustufen-Fassung (1.0.9) wirkte leblos; eigene
  Farben und SF-Symbole statt der Originale (1.0.11, Claude Lila) wirkten fremd.
- **Das Glas trägt, keine Kästen.** Wie in Apples WLAN-Menü stehen die Abschnitte
  direkt auf dem Fensterglas, getrennt durch feine Linien. Graue Modulflächen
  (bis 1.0.11) hellten das Fenster auf und ließen es neben den Systemmenüs grau
  und matt wirken. Im dunklen Modus wird das Glas zusätzlich abgedunkelt
  (`darkGlassShade`): Ein SwiftUI-Menüleistenfenster bekommt helleres Glas als die
  Systemmenüs, gemessen etwa 43 statt 30 von 255 auf demselben Hintergrund.

## 2. Farben und ihre Rollen

| Rolle | Token | Einsatz |
|---|---|---|
| Trennlinie | `separator` | zwischen den Abschnitten, eingerückt wie der Text |
| Glasabdunklung | `darkGlassShade` | ganzes Fenster, nur im dunklen Modus |
| Sekundärer Text | `secondaryText` | Bezeichnungen, „frei", Reset-Zeit, Achsen, Status |
| Dienstfarbe | `claude.color` (#D97757) / `codex.color` (#647AF8) | Balken über 20 % frei, Linie im Verlauf |
| Warnung | `warning` (Orange) | Warnsymbol bei Hinweisen und im Status |
| Kritisch | `critical` (Rot) | Balken bei 20 % frei und weniger |
| Akzent | `Color.accentColor` | Kreis des Update-Hinweises |

Regeln:
- Die Dienstfarben sind die Markenfarben, gemessen an den App-Icons. Weil Claude
  orange ist, färbt Orange keinen Balken mehr als Warnung; knapp wird ein Balken
  erst bei 20 %, dann rot. Orange als Signal bleibt nur das Warndreieck.
- Kein Grün. Rot/Grün ist das häufigste Problempaar bei Farbschwäche, und „alles
  in Ordnung" braucht keine Farbe.
- Farbe trägt nie allein Bedeutung: Jeder Balken steht neben seiner Zahl, jede
  Diagrammlinie trägt ihren Namen am Ende und eine eigene Form als Endmarke.
- **Text ist nie farbig**, sondern `.primary` oder `secondaryText`. Signalfarben
  färben nur Flächen und Symbole: Orange als Text erreicht auf heller Fläche nur
  etwa 2 : 1. Einzige Ausnahme sind Links („Manuell herunterladen") in der
  Systemlinkfarbe, an der man sie als Link erkennt.
- `secondaryText` statt des System-Sekundärgraus: Das Systemgrau kam auf der
  früheren hellen Modulfläche auf 3,9 : 1, `secondaryText` auf 5,6 : 1 (hell) und 5,9 : 1
  (dunkel), gemessen an Renderings. Ziel ist mindestens 4,5 : 1.

## 3. Typografie

Nur die macOS-Textstile, keine festen Größen. Auf macOS sind `.caption` und
`.caption2` 10 pt – zu klein für Inhalte, darum hier nicht verwendet.

| Element | Stil | Größe |
|---|---|---|
| Fenstertitel „LimitChecker" | `.headline` | 13 pt fett |
| Dienstname | `.body.weight(.semibold)` | 13 pt |
| Prozentwert | `.title3.weight(.semibold)` + `.monospacedDigit()` | 15 pt |
| Bezeichnung, „frei", Reset-Zeit, Hinweise | `.callout` | 12 pt |
| Achsen, Status | `.subheadline` | 11 pt |

- Untergrenze für Text: **11 pt**.
- Zwischen Zahl und Prozentzeichen steht ein schmales geschütztes Leerzeichen
  (`Theme.percent`), wie im deutschen Satz üblich.
- Prozentwerte immer mit gleich breiten Ziffern, auch im Diagramm, damit nichts
  springt.

## 4. Sprache

- Alles deutsch, auch die Namen der Limitfenster. Die CLIs liefern englische und
  uneinheitliche Namen; `LimitWindow.displayName` vereinheitlicht sie:
  „Current session" und „5h limit" → **5-Stunden-Fenster**, „Current week" und
  „Weekly limit" → **Woche**. Übersetzt wird nur, was mit einem dieser
  Grundnamen als ganzes Wort *beginnt*; der Rest bleibt erhalten („(Opus)",
  „(alle Modelle)"). Unbekannte Namen wie „Biweekly limit" oder „Current weekly
  limit" erscheinen unverändert – lieber englisch als falsch übersetzt.
- Reset-Zeiten: „Reset heute 15:40", „Reset morgen 02:00", „Reset gestern 15:40",
  „Reset 29. Okt., 02:00". Uhrzeiten immer zweistellig im 24-Stunden-Format.
- Der Termin wird als fester Zeitpunkt bestimmt: relativ zum **Empfangszeitpunkt**
  (wenn das Ergebnis der Abfrage eintrifft, Sekunden nach der Messung in der CLI)
  und in der Zeitzone, die die CLI nennt („(Europe/Berlin)", auch Kürzel wie
  „(UTC)"), sonst in der Zone zum Empfangszeitpunkt. Nur die Wortwahl (heute, morgen, gestern) und die Uhrzeit
  folgen der aktuellen Uhr und Zone. Ein veralteter Wert macht so aus einem
  vergangenen Reset nie einen von morgen; auf Reisen steht der Reset in Ortszeit.
- Eine Uhrzeit ohne Datum ist ihr nächstes Vorkommen nach dem Empfang. Gibt es
  sie am Tag der Zeitumstellung zweimal, zählt die erste, solange sie noch
  bevorsteht, danach die zweite. Ein Datum ohne Jahr
  bekommt das Jahr, das am nächsten an der Messung liegt.
- Eine bloße Zahl ist keine Uhrzeit: In „Oct 22 at 2am" ist 22 der Tag.
- Sachlich, ohne Ausrufezeichen. Fehler sagen, was nicht ging und was zu tun ist.
- Deutsche Komposita mit Bindestrich („5-Stunden-Fenster").

## 5. Komponenten

**Kopfzeile** – Titel links, rechts Aktualisieren und das Optionsmenü `…`. Beide
Symbolknöpfe haben 24 × 24 pt Trefferfläche, einen Tooltip und ein
`accessibilityLabel`. Während der Aktualisierung ersetzt ein Spinner gleicher
Größe den Knopf, damit nichts verrutscht.

**Optionsmenü `…`** – Update-Einträge, dann „LimitChecker beenden". Beenden liegt
bewusst im Menü und nicht im Fenster: selten gebraucht, nicht versehentlich
klickbar.

**Dienst-Icon** (`ServiceIcon`) – das Original-Icon der installierten App,
28 pt, links vom Dienstnamen. Es wird zur Laufzeit gelesen (`ServiceIcons`), damit
keine fremden Logos im Repository liegen: Claude aus dem Bundle-Icon von
`com.anthropic.claudefordesktop`, Codex aus den Ressourcen von `com.openai.codex`
(`icon-codex-dark-color` dunkel, `icon-codex-light` hell), denn das Bundle-Icon
der Codex-App ist das ChatGPT-Logo, im Dock erscheint aber die Wolke. Ohne
installierte App: SF-Symbol auf einem Quadrat in der Dienstfarbe. Ohne aktuelle
Daten grau und halb transparent, wie bei Apple das Inaktive. Der Update-Hinweis
trägt einen Kreis in Akzentfarbe.

**Abschnitt** (`MenuSection`, `MenuSeparator`) – Inhalt 16 pt eingerückt, 12 pt
oben und unten, dazwischen eine 1-pt-Linie `separator` mit derselben Einrückung.
Reihenfolge: Kopfzeile, Claude Code, Codex, bei Bedarf der Update-Hinweis, der
Verlauf, die Statuszeile.

**Update-Hinweis** – eigener Abschnitt **nach** den Kontingenten, normaler Knopf
(`.bordered`), kein hervorgehobener. Das Fenster beantwortet zuerst, wie viel
noch frei ist; das Update meldet ohnehin der Punkt in der Menüleiste.

**Limitzeile** (`LimitRow`) – oben Bezeichnung links und Prozentwert mit „frei"
rechts, darunter der Balken (6 pt, Kapsel), darunter die Reset-Zeit. VoiceOver
liest die Zeile als eine Einheit.

**Balken** – Spur `barTrack`, Füllung in der Dienstfarbe, Rot ab 20 %. Wertänderungen gleiten in 0,35 s, außer bei „Bewegung
reduzieren".

**Verlauf** (`HistoryChart`) – ein Diagramm für beide Dienste: gemeinsame Skala
0–100 %, gemeinsame Zeitachse über 12 Stunden. **Es zeigt den groben Verlauf,
keine Einzelmessungen.** Lesbarkeit geht vor Messgenauigkeit.
- Je 10 Minuten ein Wert (der letzte darin). Minütliche Treppchen sind Rauschen.
- Zeiten ohne Messung (der Mac schlief) werden **überbrückt**, nur blasser
  (35 % Deckkraft). Die Linie bleibt durchgehend lesbar, und wer genau hinsieht,
  erkennt die geschätzten Strecken. Keine Flächen, keine „keine Daten"-Texte:
  Das war ausprobiert und hat das Diagramm mit echten, lückenhaften Daten
  zerstückelt.
- Beide Linien durchgezogen. Unterschieden werden sie über Farbe *und* die Form
  der Endmarke: Kreis für Claude, Quadrat für Codex, dieselbe Form neben dem Namen.
  Strichmuster waren ausprobiert und wirkten mit echten Daten unruhig.
- Jede Linie endet an ihrem tatsächlich letzten Wert. Rechts daneben stehen Name
  und Wert; mussten die Beschriftungen auseinanderrücken oder sind die Daten älter,
  verbindet eine feine Führungslinie Marke und Beschriftung.
- Resets müssen sichtbar sein, auch wenn der Mac sie verschlafen hat. Beide
  Linien zeigen 5-Stunden-Fenster, und jedes Fenster beginnt genau 5 Stunden vor
  seinem Reset. Darum speichert jeder Verlaufspunkt die Reset-Zeit seines Fensters
  (seit 1.0.11). Ältere Punkte erben den Fensterbeginn vom nächstjüngeren
  bekannten, angefangen beim aktuellen Wert, solange sie nicht davor liegen.
- Beginnt zwischen zwei Werten ein neues Fenster, ist das ein Reset zu genau diesem
  Zeitpunkt: Die Linie hält den alten Stand bis dahin, springt auf 100 % und fällt
  dann zum nächsten Wert. Dazu eine gestrichelte Senkrechte und „Reset" über der
  Zeichenfläche. Ein Fenster, das unbenutzt bei 100 % endete, bekommt keinen Marker.
- Nur ohne bekannten Fensterbeginn gilt die Ersatzregel: ein Anstieg zwischen zwei
  nahen Werten um mindestens 30 Punkte (`resetRise`) oder um mindestens 10 Punkte
  auf genau 100 % (`resetRiseToFull`).
- Leerzustand, Zeichnung, Beschriftung und VoiceOver lesen dieselben sichtbaren
  Daten. VoiceOver bekommt eine Zusammenfassung (Wert jetzt, Alter des letzten
  Werts, wenn er älter als 25 Minuten ist, Wert zu Beginn, Resets) und über
  `accessibilityChartDescriptor` die Messwerte als Audio-Graph. Der Descriptor
  wird bei neuen Daten aktualisiert.
- Zeitbeschriftungen sitzen exakt am Anfang, in der Mitte und am Ende.

**Zustände**
- *Laden ohne Daten:* Platzhalter in der Form echter Zeilen (`.redacted`), Balken
  ohne Füllung, damit nichts wie ein Messwert aussieht.
- *Fehler:* Hinweis im Abschnitt des Dienstes, Text in `.primary`, nur das
  Warndreieck in `warning`. Liegen ältere Werte vor, bleiben sie stehen und der
  Hinweis steht darunter.
- *Leer:* Ein Satz, was passiert, kein leeres Diagramm.
- *Status* (Fußzeile): „Aktuell · 21:20"; bei Problemen mit Warndreieck davor.

## 6. Layout

- Fensterbreite 400 pt. Aller Text und alle Trennlinien beginnen 16 pt vom Rand,
  wie in Apples Menüs; nichts reicht bis an den Fensterrand.
- Keine eigenen Radien: Das Fenster rundet das Glas selbst.

## 7. Bewegung

| Was | Dauer | Kurve |
|---|---|---|
| Balken bei Wertänderung | 0,35 s | easeOut |

Sonst keine Animation. Bei „Bewegung reduzieren" entfällt auch diese.

## 8. Do's und Don'ts

**Do**
- Neue Werte als Token in `enum Theme` anlegen, nicht als Zahl in einer View.
- Neue Inhalte in einen vorhandenen Abschnitt oder eine neue `MenuSection` setzen.
- Das Fenster mit dem echten Glas prüfen, nicht nur offscreen: Offscreen-Renderings
  zeigen das Material nicht.
- Für jeden Zustand (Laden, Fehler, leer) eine Darstellung vorsehen.
- Vorher/Nachher hell und dunkel rendern, bevor eine Änderung veröffentlicht wird.

**Don't**
- Keine `.caption`- oder `.caption2`-Schrift für Inhalte (10 pt).
- Keine selbst gezeichneten Dienstlogos und keine erfundenen Dienstfarben.
- Keine Graustufen-Balken: Ein Balken trägt die Farbe seines Dienstes oder Rot.
- Keine Signalfarbe als Textfarbe.
- Keine Flächen hinter Abschnitten, keine Schlagschatten.
- Keine bekannten Limitnamen auf Englisch; unbekannte nicht raten, sondern
  unverändert zeigen (siehe 4).
- Kein Hinweistext auf einer Diagrammlinie.

## 9. Kurzbrief für KI-Agenten

> Natives macOS-Menüleistenfenster, 400 pt breit. Abschnitte direkt auf dem Glas
> wie in Apples WLAN-Menü, 16 pt eingerückt, getrennt durch `primary`-12-%-Linien;
> dunkel 30 % Schwarz über dem Glas. Systemtextstile, nie unter 11 pt; Prozentwert
> 15 pt halbfett mit gleich breiten Ziffern; sekundärer Text `primary` 72 %. Jeder
> Dienst mit Original-App-Icon (28 pt, zur Laufzeit gelesen) und Markenfarbe –
> Claude #D97757, Codex #647AF8 – in Balken und Verlauf; Rot ≤ 20 % übernimmt den
> Balken; nie farbiger Text. Verlauf grob (10-Minuten-Werte,
> Lücken blass überbrückt, Resets am echten Zeitpunkt), Endmarken Kreis/Quadrat,
> direkt beschriftet. Alles deutsch, Werte in `enum Theme`.
