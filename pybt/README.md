PyBT
====

Some basic Python bindings to OS X's CoreBluetooth framework.

Requirements
------------

* PyObjC 2.5+ with the Cocoa framework: `pip install --user -U -r
  requirements.txt`.

I elected not to use virtualenv since it's just one dependency, and I
figured the virtualenv would be more trouble than it's worth.  If
you'd prefer me to use virtualenv, let me know and I'll be happy to do
it.

Building
--------

    (cd hello/pybt && xcodebuild -configuration Release)

Do _not_ build this with the Xcode app, since it will place built
products in ~/Library/Developer/Xcode/DerivedData/, instead of
building things relative to the project path.

Testing
-------

    ./example.py

Voila.
