// SPDX-License-Identifier: GPL-3.0-only
// Text that never interprets markup: device names and command output are
// untrusted, and Text.AutoText would render `<img src=...>` as rich text.
import QtQuick
import qs.Commons as Commons

Text {
  textFormat: Text.PlainText
  color: Commons.Color.foreground
  font.family: Commons.Style.font.family
  font.pixelSize: Commons.Style.font.body
  elide: Text.ElideRight
  Accessible.role: Accessible.StaticText
  Accessible.name: text
}
