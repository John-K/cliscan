PyBT
====

Some basic Python bindings to OS X's CoreBluetooth framework.

Building
--------

    pip install --user -U pyobjc-core
    pip install --user -U pyobjc-framework-Cocoa
    (cd hello/pybt && xcodebuild -configuration Debug)

Notes:

* These command-line tools require PyObjC 2.5+. OS X 10.8 comes with
  PyObjC, but the version is older than 2.5+, so you need to do the
  `pip install` command above.  You must use `--user` when installing,
  because you definitely do not want to overwrite the system version
  (you could break many Apple programs), and you must use `-U`, to
  tell pip to perform an upgrade.

* Do _not_ build this with the Xcode app, since it will place built
  products in ~/Library/Developer/Xcode/DerivedData/, instead of
  building things relative to the project path.

Testing
-------

    ./bandsh Band

Voila.
 
