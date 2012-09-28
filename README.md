<<<<<<< HEAD

#wsabi2

##About

wsabi, short for *web services for acquiring biometric information*, is a reference application that demonstrates the capabilities of the WS-Biometric Devices protocol as defined by NIST Special Publication 500-288, *Specification for WS-Biometric Devices. 

##Design notes
* WSCDDeviceDefinition stores modalities and submodalities as delimited strings, not as arrays. The reason is that we need to be able to quickly filter all available device defs to present the "recent sensors" list, and arrays (which are stored as blobs) are not searchable. Further, these aren't going to be particularly large strings – even when including all submodalities for all modalities.
 
##Logging
The touch log files contain data in the following format, separated by commas:  
	
	Timestamp
	Class
	TouchType
	Frame(X,Y,W,H)
	Touch Point in Local Coords(X,Y)
	Touch Point in Window Coords(X,Y)
	Scroll Offset(X,Y) *when available

They are available in the iTunes File Sharing directory for wsabi2 (Device->Apps->bottom of screen->choose wsabi2->log12345.txt). For the moment, when logging a scroll action, the touch point (which isn't available) is logged as (-1,-1).

##Pending issues
* The non-keyboard-hiding behavior in the sensor walkthrough is actually not a bug, according to Apple. [linky.](http://stackoverflow.com/questions/8379205/uitextfields-keyboard-wont-dismiss-no-really) It really does still need to be addressed.  
* The WSCDPerson->WSCDItem relationship should be ordered to reflect the fact that the items are, conceptually, ordered. However, there's a longstanding bug in Apple's Core Data code which makes this impractical for the time being ([source](http://stackoverflow.com/questions/7385439/problems-with-nsorderedset)). It's my feeling that a custom overridden setter for an autogenerated property is uglier than just including some sort of index in the data model itself.  
* Currently, four separate controllers are being used for teh modality/sensors setup walkthrough; this should probably be reduced.
    
=======
#wsabi2

##About

wsabi, short for *web services for acquiring biometric information*, is a reference application that demonstrates the capabilities of the WS-Biometric Devices protocol as defined by NIST Special Publication 500-288, *Specification for WS-Biometric Devices. 

##Design notes
* WSCDDeviceDefinition stores modalities and submodalities as delimited strings, not as arrays. The reason is that we need to be able to quickly filter all available device defs to present the "recent sensors" list, and arrays (which are stored as blobs) are not searchable. Further, these aren't going to be particularly large strings – even when including all submodalities for all modalities.
 
##Logging
The touch log files contain data in the following format, separated by commas:  
	
	Timestamp
	Class
	TouchType
	Frame(X,Y,W,H)
	Touch Point in Local Coords(X,Y)
	Touch Point in Window Coords(X,Y)
	Scroll Offset(X,Y) *when available

They are available in the iTunes File Sharing directory for wsabi2 (Device->Apps->bottom of screen->choose wsabi2->log12345.txt). For the moment, when logging a scroll action, the touch point (which isn't available) is logged as (-1,-1).

##Pending issues
* The non-keyboard-hiding behavior in the sensor walkthrough is actually not a bug, according to Apple. [linky.](http://stackoverflow.com/questions/8379205/uitextfields-keyboard-wont-dismiss-no-really) It really does still need to be addressed.  
* The WSCDPerson->WSCDItem relationship should be ordered to reflect the fact that the items are, conceptually, ordered. However, there's a longstanding bug in Apple's Core Data code which makes this impractical for the time being ([source](http://stackoverflow.com/questions/7385439/problems-with-nsorderedset)). It's my feeling that a custom overridden setter for an autogenerated property is uglier than just including some sort of index in the data model itself.  
* Currently, four separate controllers are being used for teh modality/sensors setup walkthrough; this should probably be reduced.
    
>>>>>>> Development
