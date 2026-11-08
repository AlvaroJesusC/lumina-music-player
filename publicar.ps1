param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Version,

    [Parameter(Mandatory=$false, Position=1)]
    [string]$Notas = "Mejoras de rendimiento y correccion de errores."
)

$tag = $Version
if (-not ($tag.StartsWith("v") -or $tag.StartsWith("V"))) {
    $tag = "v" + $Version
}

$versionPura = $tag.Substring(1).Split('+')[0]

Write-Host ""
Write-Host "Iniciando publicacion automatica para $tag..." -ForegroundColor Cyan

# 1. Actualizar version en pubspec.yaml
$pubspecPath = "pubspec.yaml"
if (Test-Path $pubspecPath) {
    $contenido = [IO.File]::ReadAllText($pubspecPath)
    $versionNueva = "version: " + $versionPura + "+1"
    $contenidoNuevo = $contenido -replace 'version:\s*[0-9\.\+\-]+', $versionNueva
    [IO.File]::WriteAllText($pubspecPath, $contenidoNuevo)
    Write-Host "[OK] pubspec.yaml actualizado a version: $versionPura+1" -ForegroundColor Green
}

# 2. Guardar cambios en git
Write-Host "Guardando cambios en Git..." -ForegroundColor Cyan
git add .

# 3. Crear commit
git commit -m "chore(release): version $tag - $Notas"
Write-Host "[OK] Commit creado exitosamente" -ForegroundColor Green

# 4. Crear etiqueta de release
git tag -a $tag -m "$Notas"
Write-Host "[OK] Etiqueta $tag creada" -ForegroundColor Green

# 5. Enviar a GitHub
Write-Host "Subiendo cambios y etiqueta a GitHub..." -ForegroundColor Cyan
git push origin master
git push origin $tag

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "EXITO! Se ha lanzado la publicacion de $tag." -ForegroundColor Green
Write-Host "GitHub Actions esta compilando el APK en la nube en este momento." -ForegroundColor Yellow
Write-Host "En aproximadamente 2 minutos estara disponible en GitHub Releases" -ForegroundColor Yellow
Write-Host "y tu telefono mostrara la ventana para actualizar." -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Green

