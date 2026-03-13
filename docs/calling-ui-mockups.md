# Voice & Video Calling — UI Mockups

## 1. Incoming Call Dialog

```
+--------------------------------------------------+
|                                                  |
|                   (( o ))                        |
|                  /  |  \                         |
|                 /   |   \                        |
|               pulse animation                    |
|                                                  |
|                  +------+                        |
|                  |      |                        |
|                  | (AV) |  avatar                |
|                  |      |                        |
|                  +------+                        |
|                                                  |
|              Alice Johnson                       |
|            Incoming video call                   |
|                                                  |
|              #design-team                        |
|                                                  |
|                                                  |
|    +----------+   +----------+   +----------+    |
|    |          |   |          |   |          |    |
|    |  Decline |   |  Audio   |   |  Video   |    |
|    |          |   |  Only    |   |  Accept  |    |
|    |    X     |   |    ))    |   |   (>)    |    |
|    |   red    |   |  green   |   |  green   |    |
|    +----------+   +----------+   +----------+    |
|                                                  |
+--------------------------------------------------+
```

## 2. Outgoing Call (Ringing)

```
+--------------------------------------------------+
|  <- Back                                         |
|                                                  |
|                                                  |
|                                                  |
|                  +------+                        |
|                  |      |                        |
|                  | (AV) |  avatar                |
|                  |      |                        |
|                  +------+                        |
|                                                  |
|              Bob Martinez                        |
|              Ringing...                          |
|                                                  |
|              .  ..  ...  (animated dots)         |
|                                                  |
|                                                  |
|                                                  |
|                                                  |
|                                                  |
|                                                  |
|                                                  |
|                                                  |
|              +--------------+                    |
|              |              |                    |
|              |   End Call   |                    |
|              |      X       |                    |
|              |     red      |                    |
|              +--------------+                    |
|                                                  |
+--------------------------------------------------+
```

## 3. In-Call — 1:1 Video Call (Mobile)

```
+--------------------------------------------------+
| 00:05:32                      Alice Johnson   ...|
+--------------------------------------------------+
|                                                  |
|                                                  |
|                                                  |
|                                                  |
|          +------------------------------+        |
|          |                              |        |
|          |                              |        |
|          |       Alice's video          |        |
|          |       (remote, full)         |        |
|          |                              |        |
|          |                              |        |
|          |                              |        |
|          |                              |        |
|          |                              |        |
|          +------------------------------+        |
|                                                  |
|                              +----------+        |
|                              |          |        |
|                              |   You    |        |
|                              |  (self)  |  PiP   |
|                              |          |        |
|                              +----------+        |
|                                                  |
+--------------------------------------------------+
|                                                  |
|   [mic]    [cam]    [flip]   [ss]    [end]       |
|    ON       ON       __      OFF      X          |
|                                                  |
+--------------------------------------------------+
```

## 4. In-Call — Group Call, 4 Participants (Desktop)

```
+----+--------+----------------------------------------------+
|    |        |  #design-team                  00:12:47  ... |
|    |        +----------------------------------------------+
|    |        |                                              |
|    | Rooms  |   +------------------+  +------------------+ |
| S  |        |   |                  |  |                  | |
| p  | #gener |   |                  |  |                  | |
| a  | #desig*|   |   Alice Johnson  |  |   Bob Martinez   | |
| c  | #devel |   |                  |  |                  | |
| e  |--------|   |         ))       |  |                  | |
|    | DMs    |   | [speaking]       |  |                  | |
| R  |        |   +------------------+  +------------------+ |
| a  | @alice |   |                  |  |                  | |
| i  | @bob   |   |                  |  |                  | |
| l  | @carol |   |   Carol Chen     |  |   You            | |
|    |        |   |                  |  |                  | |
|    |        |   |                  |  |   [cam off]      | |
|    |        |   |                  |  |      CW          | |
|    |        |   +------------------+  +------------------+ |
|    |        |                                              |
|    |        +----------------------------------------------+
|    |        |                                              |
|    |        |    [mic]  [cam]  [screen]  [more]   [end]    |
|    |        |     ON    OFF      OFF       v        X      |
|    |        |                                              |
+----+--------+----------------------------------------------+

Legend:
  ))         = active speaker indicator (blue glow border)
  [cam off]  = avatar + initials shown when camera is disabled
  *          = active call indicator on room in list
```

## 5. In-Call — Screen Share Active (Desktop)

```
+----+--------+----------------------------------------------+
|    |        |  #design-team                  00:18:03  ... |
|    |        +----------------------------------------------+
|    |        |                                              |
|    | Rooms  |  +----------------------------------------+  |
| S  |        |  |                                        |  |
| p  | #gener |  |                                        |  |
| a  | #desig*|  |                                        |  |
| c  | #devel |  |        Alice's Screen                  |  |
| e  |--------|  |                                        |  |
|    | DMs    |  |    +--------+  +-----------+           |  |
| R  |        |  |    | Code   |  | Terminal  |           |  |
| a  | @alice |  |    | Editor |  |  $ flutter|           |  |
| i  | @bob   |  |    |        |  |    run    |           |  |
| l  | @carol |  |    +--------+  +-----------+           |  |
|    |        |  |                                        |  |
|    |        |  +----------------------------------------+  |
|    |        |                                              |
|    |        |  +--------+ +--------+ +--------+ +--------+|
|    |        |  | Alice  | |  Bob   | | Carol  | |  You   ||
|    |        |  |   ))   | |        | |        | |[camOff]||
|    |        |  +--------+ +--------+ +--------+ +--------+|
|    |        +----------------------------------------------+
|    |        |                                              |
|    |        |    [mic]  [cam]  [screen]  [more]   [end]    |
|    |        |     ON    OFF      ON        v        X      |
|    |        |                                              |
+----+--------+----------------------------------------------+

Notes:
  - Screen share takes primary area (large)
  - Video feeds collapse to filmstrip at bottom
  - Active speaker )) highlighted in filmstrip
  - [screen] button shows "ON" state (highlighted/toggled)
```

---

## Control bar icon reference

```
+-------+-------+---------+--------+-------+--------+
| [mic] | [cam] | [flip]  |  [ss]  | [more]| [end]  |
|       |       | mobile  | screen |       |        |
|       |       | only    | share  |       |        |
+-------+-------+---------+--------+-------+--------+
|  ON:  |  ON:  |  swap   |  OFF:  | menu: |  red   |
| white | white | front/  | white  | audio | circle |
| fill  | fill  | back    | outline| devs, |   X    |
|       |       |         |        | stats |        |
|  OFF: |  OFF: |         |  ON:   |       |        |
| slash | slash |         | blue   |       |        |
| thru  | thru  |         | fill   |       |        |
+-------+-------+---------+--------+-------+--------+
```
