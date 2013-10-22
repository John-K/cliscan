import objc as _objc

from .. import *

__bundle__ = _objc.initFrameworkWrapper("CoreBluetooth",
		frameworkIdentifier="com.apple.CoreBluetooth",
		frameworkPath=_objc.pathForFramework("/System/Library/Frameworks/IOBluetooth.framework/Frameworks/CoreBluetooth.framework"),
		globals=globals())
