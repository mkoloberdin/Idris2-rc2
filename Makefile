
RC2 = IDRIS2_INC_CG=rc2 idris2-rc2


all::
	idris2 --build rc2/rc2.ipkg
	${RC2} --build idris2-src/libs/prelude/prelude.ipkg
	${RC2} --build idris2-src/libs/base/base.ipkg
	${RC2} --build idris2-src/libs/contrib/contrib.ipkg
	CFLAGS="${CFLAGS} -Isupport/c/ -D_GNU_SOURCE" ${RC2} --build libs/rc2base/rc2base.ipkg
	${RC2} --build libs/control-async/control-async.ipkg
	CFLAGS="${CFLAGS} -Isupport/c" ${RC2} --build libs/web/web.ipkg
	${RC2} --build libs/termui/termui.ipkg

install::
	idris2 --install rc2/rc2.ipkg
	${RC2} --install idris2-src/libs/prelude/prelude.ipkg
	${RC2} --install idris2-src/libs/base/base.ipkg
	${RC2} --install idris2-src/libs/contrib/contrib.ipkg
	CFLAGS="${CFLAGS} -Isupport/c/ -D_GNU_SOURCE" ${RC2} --install libs/rc2base/rc2base.ipkg
	${RC2} --install libs/control-async/control-async.ipkg
	CFLAGS="${CFLAGS} -Isupport/c" ${RC2} --install libs/web/web.ipkg
	${RC2} --install libs/termui/termui.ipkg

clean::
	idris2 --clean rc2/rc2.ipkg
	idris2-rc2 --clean libs/rc2base/rc2base.ipkg
	idris2-rc2 --clean libs/control-async/control-async.ipkg
	idris2-rc2 --clean libs/web/web.ipkg
	idris2-rc2 --clean libs/termui/termui.ipkg

