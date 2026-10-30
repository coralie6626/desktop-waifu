# Builds assets/characters/waifu/waifu.png and waifu.atlas from the hand-drawn base sheet
# (tools/art/waifu_base.png) plus the parts drawn below: face variants for expressions.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tools\build_atlas.ps1
# The base sheet is never modified, so the script can be re-run after any change here.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$basePath = Join-Path $PSScriptRoot 'art\waifu_base.png'
$outDir = Join-Path $root 'assets\characters\waifu'

# Regions already on the base sheet: name, x, y, w, h.
$regions = [System.Collections.Generic.List[object]]::new()
foreach ($r in @(
	@('hair_back', 0, 0, 92, 110), @('head', 94, 0, 84, 80), @('ear', 180, 0, 26, 34),
	@('flower', 208, 0, 34, 40), @('torso', 244, 0, 44, 46), @('skirt', 290, 0, 72, 40),
	@('arm', 364, 0, 16, 40), @('leg', 382, 0, 16, 38), @('eyes', 400, 0, 48, 20),
	@('eyes_closed', 450, 0, 48, 10), @('tail', 0, 112, 30, 44)
)) { $regions.Add($r) }

function Color($r, $g, $b, $a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }

$skin = Color 255 232 220
$line = Color 110 45 30
$outline = Color 88 36 25
$white = Color 250 243 236
$iris = Color 203 138 92
$pupil = Color 122 50 32
$mouthFill = Color 196 84 84
$tongue = Color 255 150 150
$blushFill = Color 255 120 135 120
$blushLine = Color 235 95 110 200

$sheet = New-Object System.Drawing.Bitmap 512, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::Transparent)
$base = [System.Drawing.Bitmap]::FromFile($basePath)
$g.DrawImage($base, 0, 0, $base.Width, $base.Height)
$base.Dispose()
$g.SmoothingMode = 'AntiAlias'
$g.PixelOffsetMode = 'Half'

function Pen($color, $width) {
	$p = New-Object System.Drawing.Pen $color, $width
	$p.StartCap = 'Round'; $p.EndCap = 'Round'
	$p
}
function Brush($color) { New-Object System.Drawing.SolidBrush $color }

# Each new part is drawn inside its own cell; Add-Region records it for the atlas.
function Add-Region($name, $x, $y, $w, $h) { $regions.Add(@($name, $x, $y, $w, $h)) }

# --- Mouth: lift the smile off the head so it can be swapped -------------------------
# The smile sits at (129..145, 62..72) on the head; copy it out, then paint it over.
$smile = $sheet.Clone((New-Object System.Drawing.Rectangle 129, 62, 16, 10), $sheet.PixelFormat)
$g.SmoothingMode = 'None'
$g.FillRectangle((Brush $skin), 129, 63, 16, 9)
$g.SmoothingMode = 'AntiAlias'
$g.DrawImage($smile, 0, 160, 16, 10)
$smile.Dispose()
Add-Region 'mouth_smile' 0 160 16 10

# Open mouth (talking, surprised, happy).
$x = 18; $y = 160
$g.FillEllipse((Brush $mouthFill), $x + 4, $y + 2, 8, 8)
$g.FillEllipse((Brush $tongue), $x + 5.5, $y + 6, 5, 3.5)
$g.DrawEllipse((Pen $outline 1.4), $x + 4, $y + 2, 8, 8)
Add-Region 'mouth_open' $x $y 16 12

# Pout: a small downturned curve.
$x = 36; $y = 160
$g.DrawArc((Pen $line 1.8), $x + 4, $y + 4, 8, 7, 200, 140)
Add-Region 'mouth_pout' $x $y 16 10

# --- Eyes: same 48 px width and eye centres as the base "eyes" -------------------------
$eyeCentres = @(10.5, 38.5)

# Happy ^^ arcs.
$x = 56; $y = 160
foreach ($c in $eyeCentres) { $g.DrawArc((Pen $line 2.6), $x + $c - 7, $y + 3, 14, 14, 205, 130) }
Add-Region 'eyes_happy' $x $y 48 14

# Surprised: round white eyes with small irises.
$x = 106; $y = 160
foreach ($c in $eyeCentres) {
	$g.FillEllipse((Brush $white), $x + $c - 7, $y + 2, 14, 18)
	$g.FillEllipse((Brush $iris), $x + $c - 3.5, $y + 7, 7, 8)
	$g.FillEllipse((Brush $pupil), $x + $c - 2, $y + 8.5, 4, 5)
	$g.FillEllipse((Brush $white), $x + $c - 1, $y + 8.5, 2, 2)
	$g.DrawEllipse((Pen $outline 1.6), $x + $c - 7, $y + 2, 14, 18)
}
Add-Region 'eyes_surprised' $x $y 48 22

# Sleepy: the lower half of the normal eye under a heavy lid.
$x = 156; $y = 160
foreach ($c in $eyeCentres) {
	$state = $g.Save()
	$g.SetClip((New-Object System.Drawing.RectangleF ($x + $c - 9), ($y + 6), 18, 10))
	$g.FillEllipse((Brush $iris), $x + $c - 7, $y - 2, 14, 16)
	$g.FillEllipse((Brush $pupil), $x + $c - 3.5, $y + 3, 7, 8)
	$g.Restore($state)
	$g.DrawLine((Pen $line 2.6), $x + $c - 8, $y + 6, $x + $c + 8, $y + 6)
}
Add-Region 'eyes_sleepy' $x $y 48 14

# --- Blush for shy/flustered: strong cheeks with little lines --------------------------
# Cheek centres are 18 px either side of the face's centre line.
$x = 206; $y = 160
foreach ($c in @(14, 50)) {
	$g.FillEllipse((Brush $blushFill), $x + $c - 10, $y + 2, 20, 10)
	foreach ($o in @(-5, 0, 5)) { $g.DrawLine((Pen $blushLine 1.3), $x + $c + $o + 1.5, $y + 4, $x + $c + $o - 1.5, $y + 10) }
}
Add-Region 'blush' $x $y 64 14

# --- Snack Time props --------------------------------------------------------------
# Cushion she sits on: a plump pink oval with a lighter top and a button.
$x = 0; $y = 186
$cushion = Color 244 150 170
$cushionTop = Color 255 196 208
$g.FillEllipse((Brush $cushion), $x + 2, $y + 4, 92, 24)
$g.FillEllipse((Brush $cushionTop), $x + 8, $y + 5, 80, 14)
$g.DrawEllipse((Pen $outline 2), $x + 2, $y + 4, 92, 24)
$g.FillEllipse((Brush (Color 230 120 145)), $x + 45, $y + 10, 6, 4)
foreach ($t in @(2, 94)) { $g.FillEllipse((Brush $cushion), $x + $t - 3, $y + 13, 6, 6) } # tassels
Add-Region 'cushion' $x $y 96 30

# Snack: a plate of cookies and a cup of tea.
$x = 100; $y = 186
$g.FillEllipse((Brush $white), $x + 1, $y + 16, 30, 8)
$g.DrawEllipse((Pen $outline 1.4), $x + 1, $y + 16, 30, 8)
$cookie = Color 214 160 96
foreach ($c in @(@(6, 11), @(15, 9), @(12, 14))) {
	$g.FillEllipse((Brush $cookie), $x + $c[0], $y + $c[1], 11, 7)
	$g.DrawEllipse((Pen (Color 150 100 60) 1), $x + $c[0], $y + $c[1], 11, 7)
	$g.FillEllipse((Brush (Color 110 70 40)), $x + $c[0] + 4, $y + $c[1] + 2, 2, 2)
}
$g.FillRectangle((Brush $white), $x + 34, $y + 8, 11, 13)
$g.FillEllipse((Brush $white), $x + 34, $y + 17, 11, 6)
$g.FillEllipse((Brush (Color 190 120 80)), $x + 35, $y + 6, 9, 4)
$g.DrawLine((Pen $outline 1.4), $x + 34, $y + 8, $x + 34, $y + 20)
$g.DrawLine((Pen $outline 1.4), $x + 45, $y + 8, $x + 45, $y + 20)
$g.DrawEllipse((Pen $outline 1.4), $x + 34, $y + 6, 11, 4)
$g.DrawArc((Pen $outline 1.4), $x + 34, $y + 16, 11, 7, 0, 180)
$g.DrawArc((Pen $outline 1.4), $x + 43, $y + 10, 6, 7, 270, 180) # handle
Add-Region 'snack' $x $y 52 26

$g.Dispose()
$sheet.Save((Join-Path $outDir 'waifu.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

$atlas = [System.Text.StringBuilder]::new()
[void]$atlas.Append("waifu.png`nsize: 512,256`nfilter: Linear,Linear`npma: false`n")
foreach ($r in $regions) { [void]$atlas.Append("$($r[0])`nbounds: $($r[1]),$($r[2]),$($r[3]),$($r[4])`n") }
[System.IO.File]::WriteAllText((Join-Path $outDir 'waifu.atlas'), $atlas.ToString())
Write-Host "Wrote waifu.png and waifu.atlas with $($regions.Count) regions."
