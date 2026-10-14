.PHONY: gen test build install

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
