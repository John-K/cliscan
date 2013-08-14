INSTALLATION
============

1. You will need to install pip, a Python package manager, if you haven't yet.  To install pip:

    curl -O http://python-distribute.org/distribute_setup.py && python distribute_setup.py --user && rm distribute_setup*
    easy_install -U pip
    easy_install -U virtualenv
    echo 'export PATH=$PATH:$HOME/Library/Python/2.7/bin' >> ~/.profile

2. `pip install --user -U -r requirements.txt`. This will take a while
   (5-10 minutes), since it downloads and compiles a new version of
   PyObjC. (And yeah, you need the new version.)  You need the
   `--user` parameter to install PyObjC to your home directory instead
   of to /System/Library/, since you don't want to overwrite the
   system-provided PyObjC, and you need the `-U` parameter to tell pip
   to upgrade PyObjC, since a system-installed version already exists.

3. Run `./example.py`, which shouldn't do anything other than print out
   a few lines that look like `<CBCharacteristic: 0xdeadbeef>`.

4. Look at the comments in `example.py` to how to use things.
