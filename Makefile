clean:
	fvm flutter clean

get:
	fvm flutter pub get

gen:
	flutter pub run build_runner build
	
install: 
	./install.sh

clean_install: clean get gen install

clean_build: clean get gen
	fvm flutter build macos