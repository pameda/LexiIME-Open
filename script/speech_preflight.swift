import Foundation
import Speech
import AVFoundation

// Read capabilities only. This does not request permissions or activate a microphone.
let locales=["zh-CN","en-US","ja-JP","es-ES"]
let result:[String:Any]=[
    "speechAuthorization":SFSpeechRecognizer.authorizationStatus().rawValue,
    "microphoneAuthorization":AVCaptureDevice.authorizationStatus(for:.audio).rawValue,
    "languages":locales.map { locale -> [String:Any] in
        let recognizer=SFSpeechRecognizer(locale:Locale(identifier:locale))
        return ["locale":locale,"supported":recognizer != nil,"onDevice":recognizer?.supportsOnDeviceRecognition ?? false,"available":recognizer?.isAvailable ?? false]
    },
    "microphoneActivated":false
]
let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
print(String(decoding:data,as:UTF8.self))
