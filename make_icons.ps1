Add-Type -AssemblyName System.Drawing

function New-RoundPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2.0
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  $p
}

function New-Icon([int]$size, [scriptblock]$draw) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
  $g.Clear([System.Drawing.Color]::Transparent)
  & $draw $g ([double]($size / 48.0))
  $g.Dispose()
  $bmp
}

function Save-Icon($bmp, [string]$path) {
  $full = Join-Path $icoDir $path
  $bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "saved $full"
}

$icoDir = Join-Path $PSScriptRoot "dn1c_export_pdf2\ico"

function Col([int]$a, [int]$r, [int]$g, [int]$b) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }

$drawExport = {
  param($g, [double]$s)
  # Document page (white, rounded, gray border)
  $pagePath = New-RoundPath (6*$s) (4*$s) (34*$s) (40*$s) (4*$s)
  $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  $g.FillPath($white, $pagePath)
  $grayPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,207,216,220), (1.5*$s))
  $g.DrawPath($grayPen, $pagePath)
  # Red PDF header band (rounded top, square bottom)
  $hdr = New-RoundPath (6*$s) (4*$s) (34*$s) (12*$s) (4*$s)
  $band = New-Object System.Drawing.RectangleF((6*$s), (10*$s), (34*$s), (6*$s))
  $red = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,229,57,53))
  $g.FillPath($red, $hdr)
  $g.FillRectangle($red, $band)
  # White "PDF" hint line inside red band
  $wp = New-Object System.Drawing.Pen([System.Drawing.Color]::White, (2.2*$s))
  $g.DrawLine($wp, (14*$s), (10*$s), (32*$s), (10*$s))
  # Scene preview box
  $sceneBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,226,232,240))
  $sceneRect = New-Object System.Drawing.RectangleF((10*$s), (19*$s), (26*$s), (15*$s))
  $g.FillRectangle($sceneBrush, $sceneRect)
  $scenePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,203,213,225), (1.0*$s))
  $g.DrawRectangle($scenePen, $sceneRect.X, $sceneRect.Y, $sceneRect.Width, $sceneRect.Height)
  # Mountain glyph
  $pts = @(
    (New-Object System.Drawing.PointF((12*$s),(32*$s))),
    (New-Object System.Drawing.PointF((19*$s),(23*$s))),
    (New-Object System.Drawing.PointF((25*$s),(30*$s))),
    (New-Object System.Drawing.PointF((29*$s),(26*$s))),
    (New-Object System.Drawing.PointF((34*$s),(32*$s)))
  )
  $mBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180,100,116,139))
  $g.FillPolygon($mBrush, $pts)
  # Sun
  $sunBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,245,158,11))
  $g.FillEllipse($sunBrush, (14.5*$s), (21.5*$s), (3.5*$s), (3.5*$s))
  # Bottom lines
  $l1 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,148,163,184), (2*$s))
  $g.DrawLine($l1, (10*$s), (38*$s), (26*$s), (38*$s))
  $l2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,203,213,225), (1.5*$s))
  $g.DrawLine($l2, (10*$s), (41.5*$s), (20*$s), (41.5*$s))
}

$drawQuick = {
  param($g, [double]$s)
  # Dark plate
  $plate = New-RoundPath (4*$s) (4*$s) (40*$s) (40*$s) (10*$s)
  $dark = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,30,41,59))
  $g.FillPath($dark, $plate)
  $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,51,65,85), (1.5*$s))
  $g.DrawPath($borderPen, $plate)
  # Document silhouette
  $doc = New-RoundPath (12*$s) (9*$s) (22*$s) (31*$s) (1.5*$s)
  $docBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,51,65,85))
  $g.FillPath($docBrush, $doc)
  # Lightning bolt
  $bolt = @(
    (New-Object System.Drawing.PointF((28*$s),(8*$s))),
    (New-Object System.Drawing.PointF((16*$s),(26*$s))),
    (New-Object System.Drawing.PointF((24*$s),(26*$s))),
    (New-Object System.Drawing.PointF((20*$s),(42*$s))),
    (New-Object System.Drawing.PointF((34*$s),(22*$s))),
    (New-Object System.Drawing.PointF((25*$s),(22*$s)))
  )
  $boltBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,245,158,11))
  $g.FillPolygon($boltBrush, $bolt)
  $boltPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,124,45,18), (0.9*$s))
  $g.DrawPolygon($boltPen, [System.Drawing.PointF[]]$bolt)
}

$drawFrame = {
  param($g, [double]$s)
  # Dark plate
  $plate = New-RoundPath (4*$s) (4*$s) (40*$s) (40*$s) (10*$s)
  $dark = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,30,41,59))
  $g.FillPath($dark, $plate)
  $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,51,65,85), (1.5*$s))
  $g.DrawPath($borderPen, $plate)
  # Dim outer viewport
  $dimPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(160,71,85,105), (1.0*$s))
  $g.DrawRectangle($dimPen, (8*$s), (11*$s), (32*$s), (26*$s))
  # Safe frame fill + border
  $fillBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(51,3,105,161))
  $frameRect = New-Object System.Drawing.RectangleF((11*$s), (14*$s), (26*$s), (20*$s))
  $g.FillRectangle($fillBrush, $frameRect)
  $framePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,56,189,248), (2.0*$s))
  $g.DrawRectangle($framePen, $frameRect.X, $frameRect.Y, $frameRect.Width, $frameRect.Height)
  # Corner marks
  $cPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,56,189,248), (2.2*$s))
  $cPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $cPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
  $g.DrawLine($cPen, (8*$s),  (18*$s), (8*$s),  (11*$s))
  $g.DrawLine($cPen, (8*$s),  (11*$s), (15*$s), (11*$s))
  $g.DrawLine($cPen, (40*$s), (18*$s), (40*$s), (11*$s))
  $g.DrawLine($cPen, (40*$s), (11*$s), (33*$s), (11*$s))
  $g.DrawLine($cPen, (8*$s),  (30*$s), (8*$s),  (37*$s))
  $g.DrawLine($cPen, (8*$s),  (37*$s), (15*$s), (37*$s))
  $g.DrawLine($cPen, (40*$s), (30*$s), (40*$s), (37*$s))
  $g.DrawLine($cPen, (40*$s), (37*$s), (33*$s), (37*$s))
  # Center dot
  $dot = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,56,189,248))
  $g.FillEllipse($dot, (21.5*$s), (21.5*$s), (5*$s), (5*$s))
}

foreach ($spec in @(
  @{ draw = $drawExport; name = "export_dialog" },
  @{ draw = $drawQuick;  name = "quick_export" },
  @{ draw = $drawFrame;  name = "frame_overlay" }
)) {
  Save-Icon (New-Icon 16 $spec.draw) "$($spec.name).png"
  Save-Icon (New-Icon 24 $spec.draw) "$($spec.name)_large.png"
}
