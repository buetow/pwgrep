NAME=pwgrep
all: version documentation build

# THIS IS NEEDED BY THE DEBIAN TOOLS

# Builds the project. Since this is only a fake project, it just copies a script.
build:
	
# 'install' installes a fake-root, which will be used to build the Debian package
# $DESTDIR is actually set by the Debian tools.
install:
	test ! -d $(DESTDIR)/usr/bin && mkdir -p $(DESTDIR)/usr/bin || exit 0
	test ! -d $(DESTDIR)/usr/share/$(NAME) && mkdir -p $(DESTDIR)/usr/share/$(NAME) || exit 0
	test ! -d $(DESTDIR)/usr/share/man/man1 && mkdir -p $(DESTDIR)/usr/share/man/man1 || exit 0
	cp ./bin/$(NAME).sh $(DESTDIR)/usr/share/$(NAME)/
	chmod 755 ./bin/$(NAME).sh $(DESTDIR)/usr/share/$(NAME)/$(NAME).sh
	cp ./docs/$(NAME).1.gz $(DESTDIR)/usr/share/man/man1/$(NAME).1.gz
	bash -c 'for i in fwipe pwdbls pwedit pwfadd pwfcat pwfdel pwfls pwgrep \
		pwhelp pwldb pwupdate; do \
			ln -s $(DESTDIR)/share/$(NAME)/$(NAME).sh $(DESTDIR)/usr/bin/$$i; \
			cp ./docs/$(NAME).1.gz $(DESTDIR)/usr/share/man/man1/$$i.1.gz; \
		done 2>/dev/null || exit 0'

deinstall:
	bash -c 'for i in fwipe pwdbls pwedit pwfadd pwfcat pwfdel pwfls pwgrep \
		pwhelp pwldb pwupdate; do \
			rm $(DESTDIR)/usr/bin/$$i; \
			rm $(DESTDIR)/usr/share/man/man1/$$i.1.gz; \
		done 2>/dev/null || exit 0'
	test -d $(DESTDIR)/usr/share/$(NAME) && rm -r $(DESTDIR)/usr/share/$(NAME) || exit 0
	test -f $(DESTDIR)/usr/share/man/man1/$(NAME).1.gz && rm -f $(DESTDIR)/usr/share/man/man1/$(NAME).1.gz || exit 0

uninstall: deinstall

clean:

# ADDITIONAL RULES:

# Parses the version out of the Debian changelog
version:
	cut -d' ' -f2 debian/changelog | head -n 1 | sed 's/(//;s/)//' > .version

# Builds the documentation into a manpage
documentation:
	pod2man --release="$(NAME) $$(cat .version)" \
		--center="User Commands" ./docs/$(NAME).pod > ./docs/$(NAME).1
	[ -f ./docs/$(NAME).1.gz ] && rm -f ./docs/$(NAME).1.gz
	gzip ./docs/$(NAME).1
	pod2text ./docs/$(NAME).pod > ./docs/$(NAME).txt

# Build a debian package (don't sign it, modify the arguments if you want to sign it)
deb: all
	dpkg-buildpackage -uc -us

dch: 
	dch -i

release: dch deb 
	bash -c "git tag $$(cat .version)"
	git push --tags
	git commit -a -m 'New release'
	git push origin master

clean-top:
	rm ../$(NAME)_*.tar.gz
	rm ../$(NAME)_*.dsc
	rm ../$(NAME)_*.changes
	rm ../$(NAME)_*.deb

