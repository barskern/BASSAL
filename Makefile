DIST=dist
SRC=src

.PHONY: all clean

all: main user chroot live reboot

%: $(SRC)/env.sh $(SRC)/%.base
	cat $(SRC)/env.sh $(SRC)/$@.base > $(DIST)/bassal_$@.sh

clean: 
	rm $(DIST)/*

