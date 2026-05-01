clean:
	flutter clean

get:
	flutter pub get

gen:
	dart run build_runner build --delete-conflicting-outputs
	
install: clean get gen
	./install.sh