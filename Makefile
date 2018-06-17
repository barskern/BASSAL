
SRC=src

.PHONY: all clean

all: main user chroot live

%: $(SRC)/env.sh $(SRC)/%.base
	cat $(SRC)/env.sh $(SRC)/$@.base > bassal_$@.sh

clean: 
	rm bassal_*.sh

