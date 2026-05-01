clean:
	fvm flutter clean

get:
	fvm flutter pub get

gen:
	dart run build_runner build --delete-conflicting-outputs
	
install: 
	./install.sh

clean_install: clean get gen install