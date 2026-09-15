param([string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
[xml]$svg = Get-Content -LiteralPath (Join-Path $ProjectRoot 'App/Brand/watchdog-app-icon.svg') -Raw
$pathData = $svg.svg.path.d
$bitmap = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#153C32'))
$shape = [System.Drawing.Drawing2D.GraphicsPath]::new([System.Drawing.Drawing2D.FillMode]::Alternate)
$previous = [System.Drawing.PointF]::new(0, 0)
foreach ($match in [regex]::Matches($pathData, '([ML])([\d.]+),([\d.]+)|(Z)')) {
    if ($match.Groups[4].Success) { $shape.CloseFigure(); continue }
    $next = [System.Drawing.PointF]::new(([single]$match.Groups[2].Value + 34) * 2.56, ([single]$match.Groups[3].Value + 34) * 2.56)
    if ($match.Groups[1].Value -eq 'M') { $shape.StartFigure() }
    else { $shape.AddLine($previous, $next) }
    $previous = $next
}
$brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#F5F4ED'))
$graphics.FillPath($brush, $shape)
$destination = Join-Path $ProjectRoot 'App/Assets.xcassets/AppIcon.appiconset/Watchdog-1024.png'
$bitmap.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png)
$brush.Dispose(); $shape.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
Write-Output 'Rendered opaque 1024px app icon from editable Watchdog vector geometry.'
