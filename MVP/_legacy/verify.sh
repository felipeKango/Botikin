#!/bin/zsh
# verify.sh — chequeos del MVP de Botikin.
# Corre todo lo verificable según las herramientas disponibles:
# con solo Command Line Tools hace build + sintaxis; con Xcode
# corre además los tests XCTest y compila la app para simulador.
set -u
cd "$(dirname "$0")"

PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
skip() { echo "  ⏭️  $1"; }

echo "── BotikinKit (lógica de negocio) ─────────────────────"
if (cd ios/BotikinKit && swift build >/dev/null 2>&1); then
  ok "swift build BotikinKit"
else
  bad "swift build BotikinKit"
fi

HAS_XCODE=0
if [ -d /Applications/Xcode.app ] && xcodebuild -version >/dev/null 2>&1; then
  HAS_XCODE=1
fi

if [ $HAS_XCODE -eq 1 ]; then
  if (cd ios/BotikinKit && swift test 2>&1 | tail -1 | grep -q "passed"); then
    ok "swift test BotikinKit (XCTest)"
  else
    bad "swift test BotikinKit (XCTest)"
  fi
else
  skip "swift test: requiere Xcode (XCTest no viene en Command Line Tools)"
fi

echo "── Sintaxis Swift (app + paquete) ─────────────────────"
SWIFT_ERR=0
for f in $(find ios/Botikin ios/BotikinKit/Sources ios/BotikinKit/Tests -name "*.swift"); do
  if ! swiftc -parse "$f" >/dev/null 2>&1; then
    SWIFT_ERR=1; echo "     error de sintaxis: $f"
  fi
done
N=$(find ios/Botikin ios/BotikinKit/Sources ios/BotikinKit/Tests -name "*.swift" | wc -l | tr -d ' ')
[ $SWIFT_ERR -eq 0 ] && ok "sintaxis de $N archivos Swift" || bad "sintaxis Swift"

echo "── App iOS (simulador) ────────────────────────────────"
if [ $HAS_XCODE -eq 1 ]; then
  if [ ! -f ios/Botikin/Resources/Secrets.plist ]; then
    skip "build app: falta ios/Botikin/Resources/Secrets.plist"
  elif (cd ios && xcodebuild -project Botikin.xcodeproj -scheme Botikin \
        -destination 'generic/platform=iOS Simulator' \
        -skipPackagePluginValidation build 2>&1 | grep -q "BUILD SUCCEEDED"); then
    ok "xcodebuild app para simulador"
  else
    bad "xcodebuild app para simulador (corre a mano para ver el error)"
  fi
else
  skip "xcodebuild: requiere Xcode instalado"
fi

echo "── Edge Functions (TypeScript) ────────────────────────"
if command -v deno >/dev/null 2>&1; then
  TS_ERR=0
  for f in supabase/functions/*/index.ts; do
    deno check "$f" >/dev/null 2>&1 || { TS_ERR=1; echo "     deno check falló: $f"; }
  done
  [ $TS_ERR -eq 0 ] && ok "deno check de las funciones" || bad "deno check"
elif command -v npx >/dev/null 2>&1; then
  TS_ERR=0
  for f in $(find supabase/functions -name "*.ts"); do
    npx -y esbuild "$f" --loader:.ts=ts --outfile=/dev/null >/dev/null 2>&1 \
      || { TS_ERR=1; echo "     sintaxis TS inválida: $f"; }
  done
  NT=$(find supabase/functions -name "*.ts" | wc -l | tr -d ' ')
  [ $TS_ERR -eq 0 ] && ok "sintaxis de $NT archivos TS (esbuild)" || bad "sintaxis TS"
else
  skip "TS: no hay deno ni npx disponibles"
fi

echo "── Recursos y configuración ───────────────────────────"
if plutil -lint ios/Botikin/Resources/*.plist >/dev/null 2>&1; then
  ok "plists válidos"
else
  bad "plutil -lint"
fi
if python3 -c "
import json,glob,sys
for f in glob.glob('ios/Botikin/Resources/Assets.xcassets/**/Contents.json', recursive=True):
    json.load(open(f))
" >/dev/null 2>&1; then
  ok "asset catalog JSON válido"
else
  bad "asset catalog JSON"
fi
[ -f ios/Botikin/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png ] \
  && ok "ícono 1024px presente" || bad "falta el ícono 1024px"
[ -f ios/Botikin/Resources/Secrets.plist ] \
  && ok "Secrets.plist presente" \
  || skip "Secrets.plist: copia Secrets.example.plist y completa tus valores"

echo "── Supabase local (opcional) ──────────────────────────"
if command -v supabase >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  if supabase status >/dev/null 2>&1; then
    ok "supabase local corriendo"
  else
    skip "supabase local detenido (levanta con: supabase start)"
  fi
else
  skip "supabase local: requiere Docker corriendo"
fi

echo "───────────────────────────────────────────────────────"
echo "Resultado: $PASS OK · $FAIL con error"
exit $([ $FAIL -eq 0 ] && echo 0 || echo 1)
