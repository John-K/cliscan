import objc as _objc

__bundle__ = _objc.initFrameworkWrapper("IOBluetooth",
		frameworkIdentifier="com.apple.Bluetooth",
		frameworkPath=_objc.pathForFramework("/System/Library/Frameworks/IOBluetooth.framework"),
		globals=globals())
