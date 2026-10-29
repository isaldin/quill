.PHONY: gen test build install release publish cask icon

VERSION := $(shell sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
ZIP := build/Quill-$(VERSION).zip
TAP_DIR ?= ../homebrew-tap

gen:
	xcodegen generate

test:
	swift test --package-path Core

build: gen
	xcodebuild -project Quill.xcodeproj -scheme Quill -configuration Debug \
		-derivedDataPath build -allowProvisioningUpdates -quiet build

install: build
	-pkill -x Quill
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/Quill.app
	cp -R build/Build/Products/Debug/Quill.app $(HOME)/Applications/
	open $(HOME)/Applications/Quill.app

# Оптимизированная сборка для переноса на другой Mac: build/Quill-<версия>.zip (ditto сохраняет подпись).
release: gen
	xcodebuild -project Quill.xcodeproj -scheme Quill -configuration Release \
		-derivedDataPath build -allowProvisioningUpdates -quiet build
	rm -f $(ZIP)
	ditto -c -k --keepParent build/Build/Products/Release/Quill.app $(ZIP)
	@echo "Готово: $(ZIP)"

# Тег v<версия> из project.yml и GitHub Release с zip. Версию поднимать в project.yml до запуска.
publish: release
	@test -z "$$(git status --porcelain)" || { echo "Есть незакоммиченные изменения"; exit 1; }
	git tag v$(VERSION)
	git push origin v$(VERSION)
	gh release create v$(VERSION) $(ZIP) --verify-tag --title "Quill $(VERSION)" --generate-notes

# Cask для tap-репозитория isaldin/homebrew-tap (клон в TAP_DIR); коммит и push — вручную.
cask:
	@test -f $(ZIP) || { echo "Нет $(ZIP): сначала make release"; exit 1; }
	mkdir -p $(TAP_DIR)/Casks
	sed -e "s/@VERSION@/$(VERSION)/" -e "s/@SHA256@/$$(shasum -a 256 $(ZIP) | cut -d' ' -f1)/" \
		packaging/homebrew/quill.rb > $(TAP_DIR)/Casks/quill.rb
	@echo "Готово: $(TAP_DIR)/Casks/quill.rb"

# Иконка приложения: scripts/render-app-icon.swift → все размеры AppIcon.appiconset.
ICONSET := App/Resources/Assets.xcassets/AppIcon.appiconset
icon:
	swift scripts/render-app-icon.swift build/icon-1024.png
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s build/icon-1024.png --out $(ICONSET)/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s * 2)) $$((s * 2)) build/icon-1024.png --out $(ICONSET)/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
