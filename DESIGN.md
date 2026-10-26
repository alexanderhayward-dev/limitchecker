---
version: 1
name: LimitChecker
description: |
  Detailfenster einer macOS-Menüleisten-App. Native Systemschrift und
  Systemfarben, Module im Stil des Kontrollzentrums auf dem Fenstermaterial,
  Farbe nur als Signal. Hell und dunkel ohne eigene Varianten, weil alles aus
  Systemfarben und Deckkraftstufen von `.primary` gebaut ist.

tokens: Sources/LimitChecker/LimitCheckerApp.swift → enum Theme

colors:
  platter-fill: "primary 5 %"        # Modulfläche
  hairline: "primary 8 %"            # Modulrand
  bar-track: "primary 10 %"          # leere Balkenspur
  bar-neutral: "primary 55 %"        # Balken im Normalfall
  gridline: "secondary 25 %"         # Diagrammraster
  secondary-text: "primary 72 %"     # sekundärer Text, gemessen ≥ 5,6 : 1
  warning: "systemOrange"            # Balken ≤ 50 %, Warnsymbole – nie Text
  critical: "systemRed"              # Balken ≤ 20 %
  series-claude: "systemPurple"      # nur im Verlauf, Endmarke Kreis
  series-codex: "systemBlue"         # nur im Verlauf, Endmarke Quadrat

typography:   # macOS-Textstile, gemessen
  headline: 13 pt fett       # Fenstertitel
  body-semibold: 13 pt       # Modultitel
  title3-semibold: 15 pt     # Prozentwert, Ziffern gleich breit
  callout: 12 pt             # Bezeichnungen, Reset-Zeit, Hinweise, Fließtext
  subheadline: 11 pt         # Achsen, Status

spacing: { outer: 12, platter-padding: 12, platter-gap: 8, row-gap: 12, bar: 6 }
radius: { platter: 10, bar: Kapsel }
width: 400
hit-target: 24
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
- **Farbe ist Signal, keine Dekoration.** Im Normalfall ist das Fenster
  grau-weiß. Farbe erscheint erst, wenn etwas Aufmerksamkeit braucht.
- **Tiefe durch Flächen, nicht durch Schatten.** Module heben sich durch eine
  leichte Fläche und eine Haarlinie vom Fenstermaterial ab.

## 2. Farben und ihre Rollen

| Rolle | Token | Einsatz |
|---|---|---|
| Modulfläche | `platterFill` | Hintergrund jedes Moduls |
| Haarlinie | `hairline` | Modulrand |
| Sekundärer Text | `secondaryText` | Bezeichnungen, „frei", Reset-Zeit, Achsen, Status |
| Balken neutral | `barNeutral` | Balken bei mehr als 50 % frei |
| Warnung | `warning` (Orange) | Balken bei 21–50 % frei, Warnsymbol bei Hinweisen und im Status |
| Kritisch | `critical` (Rot) | Balken bei 20 % frei und weniger |
| Serie Claude / Codex | `claudeSeries` / `codexSeries` | **nur** die Linien im Verlauf |

Regeln:
- Orange bedeutet überall dasselbe: *Achtung*. Darum sind die Serienfarben Lila
  und Blau und nie Orange, Rot oder Grün.
- Kein Grün. Rot/Grün ist das häufigste Problempaar bei Farbschwäche, und „alles
  in Ordnung" braucht keine Farbe.
- Farbe trägt nie allein Bedeutung: Jeder Balken steht neben seiner Zahl, jede
  Diagrammlinie trägt ihren Namen am Ende und eine eigene Form als Endmarke.
- **Text ist nie farbig**, sondern `.primary` oder `secondaryText`. Signalfarben
  färben nur Flächen und Symbole: Orange als Text erreicht auf heller Fläche nur
  etwa 2 : 1. Einzige Ausnahme sind Links („Manuell herunterladen") in der
  Systemlinkfarbe, an der man sie als Link erkennt.
- `secondaryText` statt des System-Sekundärgraus: Das Systemgrau kam auf der
  hellen Modulfläche auf 3,9 : 1, `secondaryText` auf 5,6 : 1 (hell) und 5,9 : 1
  (dunkel), gemessen an Renderings. Ziel ist mindestens 4,5 : 1.

## 3. Typografie

Nur die macOS-Textstile, keine festen Größen. Auf macOS sind `.caption` und
`.caption2` 10 pt – zu klein für Inhalte, darum hier nicht verwendet.

| Element | Stil | Größe |
|---|---|---|
| Fenstertitel „LimitChecker" | `.headline` | 13 pt fett |
| Modultitel | `.body.weight(.semibold)` | 13 pt |
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

**Modul** (`Platter`) – Fläche `platterFill`, Haarlinie, Radius 10 pt
(continuous), Innenabstand 12 pt. Reihenfolge: Claude Code, Codex, bei Bedarf
der Update-Hinweis, dann der Verlauf. Keine Trennlinien zwischen Modulen.

**Update-Hinweis** – eigenes Modul **nach** den Kontingenten, normaler Knopf
(`.bordered`), kein hervorgehobener. Das Fenster beantwortet zuerst, wie viel
noch frei ist; das Update meldet ohnehin der Punkt in der Menüleiste.

**Limitzeile** (`LimitRow`) – oben Bezeichnung links und Prozentwert mit „frei"
rechts, darunter der Balken (6 pt, Kapsel), darunter die Reset-Zeit. VoiceOver
liest die Zeile als eine Einheit.

**Balken** – Spur `barTrack`, Füllung nach Schwelle: neutral über 50 %, Orange ab
50 %, Rot ab 20 %. Wertänderungen gleiten in 0,35 s, außer bei „Bewegung
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
- Reset: Ein deutlicher Anstieg zwischen zwei gemessenen Werten – mindestens 30
  Punkte (`resetRise`) oder um mindestens 10 Punkte auf genau 100 %
  (`resetRiseToFull`) – bekommt eine gestrichelte Senkrechte und das Wort „Reset"
  über der Zeichenfläche. In einer überbrückten Strecke wird kein Reset-Zeitpunkt
  behauptet.
- Leerzustand, Zeichnung, Beschriftung und VoiceOver lesen dieselben sichtbaren
  Daten. VoiceOver bekommt eine Zusammenfassung (Wert jetzt, Alter des letzten
  Werts, wenn er älter als 25 Minuten ist, Wert zu Beginn, Resets) und über
  `accessibilityChartDescriptor` die Messwerte als Audio-Graph. Der Descriptor
  wird bei neuen Daten aktualisiert.
- Zeitbeschriftungen sitzen exakt am Anfang, in der Mitte und am Ende.

**Zustände**
- *Laden ohne Daten:* Platzhalter in der Form echter Zeilen (`.redacted`), Balken
  ohne Füllung, damit nichts wie ein Messwert aussieht.
- *Fehler:* Hinweis im Modul des Dienstes, Text in `.primary`, nur das
  Warndreieck in `warning`. Liegen ältere Werte vor, bleiben sie stehen und der
  Hinweis steht darunter.
- *Leer:* Ein Satz, was passiert, kein leeres Diagramm.
- *Status* (Fußzeile): „Aktuell · 21:20"; bei Problemen mit Warndreieck davor.

## 6. Layout

- Fensterbreite 400 pt, Außenabstand 12 pt, Abstand zwischen Modulen 8 pt.
- Kopfzeile und Statuszeile sind um den Modul-Innenabstand eingerückt, damit ihr
  Text auf einer Kante mit dem Inhalt der Module steht.
- Verschachtelte Radien: Die Formel *innen = außen − Abstand* ergäbe beim
  Fensterradius und 12 pt Abstand einen Wert unter 2. Die Module behalten deshalb
  ihre eigenen 10 pt.

## 7. Bewegung

| Was | Dauer | Kurve |
|---|---|---|
| Balken bei Wertänderung | 0,35 s | easeOut |

Sonst keine Animation. Bei „Bewegung reduzieren" entfällt auch diese.

## 8. Do's und Don'ts

**Do**
- Neue Werte als Token in `enum Theme` anlegen, nicht als Zahl in einer View.
- Neue Inhalte in ein vorhandenes Modul oder ein neues `Platter` setzen.
- Für jeden Zustand (Laden, Fehler, leer) eine Darstellung vorsehen.
- Vorher/Nachher hell und dunkel rendern, bevor eine Änderung veröffentlicht wird.

**Don't**
- Keine `.caption`- oder `.caption2`-Schrift für Inhalte (10 pt).
- Keine Serienfarbe in Orange, Rot oder Grün.
- Keine Signalfarbe als Textfarbe.
- Keine Trennlinien zwischen Modulen, keine Schlagschatten.
- Keine bekannten Limitnamen auf Englisch; unbekannte nicht raten, sondern
  unverändert zeigen (siehe 4).
- Kein Hinweistext auf einer Diagrammlinie.

## 9. Kurzbrief für KI-Agenten

> Natives macOS-Menüleistenfenster, 400 pt breit. Module wie im Kontrollzentrum:
> `primary` 5 % Fläche, 8 % Haarlinie, Radius 10. Systemtextstile, nie unter
> 11 pt; Prozentwert 15 pt halbfett mit gleich breiten Ziffern; sekundärer Text
> `primary` 72 %. Farbe nur als Signal auf Flächen und Symbolen (Orange ≤ 50 %,
> Rot ≤ 20 %), nie als Text; Verlauf grob (10-Minuten-Werte, Lücken blass
> überbrückt), Serien Lila (Kreis) und Blau (Quadrat), direkt beschriftet. Alles deutsch, Werte in `enum Theme`.
