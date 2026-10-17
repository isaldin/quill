.PHONY: gen test build install release

gen:
	xcodegen generate

test:
	swift test --package-path Core

build: gen
	xcodebuild -project OpenWhisper.xcodeproj -scheme OpenWhisper -configuration Debug \
		-derivedDataPath build -allowProvisioningUpdates -quiet build

install: build
	-pkill -x OpenWhisper
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/OpenWhisper.app
	cp -R build/Build/Products/Debug/OpenWhisper.app $(HOME)/Applications/
	open $(HOME)/Applications/OpenWhisper.app

# Оптимизированная сборка для переноса на другой Mac: build/OpenWhisper.zip (ditto сохраняет подпись).
release: gen
	xcodebuild -project OpenWhisper.xcodeproj -scheme OpenWhisper -configuration Release \
		-derivedDataPath build -allowProvisioningUpdates -quiet build
	rm -f build/OpenWhisper.zip
	ditto -c -k --keepParent build/Build/Products/Release/OpenWhisper.app build/OpenWhisper.zip
	@echo "Готово: build/OpenWhisper.zip"
