//
//  SaySomething-Bridging-Header.h
//  Exposes whisper.cpp's plain-C API (ios/Vendor/whisper.cpp/whisper.h) to
//  Swift. Only the main App target links this header (see
//  SWIFT_OBJC_BRIDGING_HEADER in project.pbxproj) — SaySomethingKeyboard
//  never sees whisper.cpp at all (PRD 階段 7 C2: keyboard extension stays
//  under the 60-70MB extension memory ceiling).
//
#ifndef SaySomething_Bridging_Header_h
#define SaySomething_Bridging_Header_h

#import "whisper.h"

#endif /* SaySomething_Bridging_Header_h */
