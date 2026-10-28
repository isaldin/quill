.PHONY: gen test build install release

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

# Оптимизированная сборка для переноса на другой Mac: build/Quill.zip (ditto сохраняет подпись).
release: gen
	xcodebuild -project Quill.xcodeproj -scheme Quill -configuration Release \
		-derivedDataPath build -allowProvisioningUpdates -quiet build
	rm -f build/Quill.zip
	ditto -c -k --keepParent build/Build/Products/Release/Quill.app build/Quill.zip
	@echo "Готово: build/Quill.zip"
