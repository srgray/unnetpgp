//
//  UNNetPGP_Tests.m
//  UNNetPGP Tests
//
//  Created by Tom Whipple on 11/9/13.
//  Copyright (c) 2013 Tom Whipple. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "UNNetPGP.h"

#define PLAINTEXT @"Plaintext: Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse blandit justo eros.\n"
#define PASSWORD @"take out the garbage"

NSString* getUUID(void){
  CFUUIDRef theUUID = CFUUIDCreate(NULL);
  CFStringRef string = CFUUIDCreateString(NULL, theUUID);
  CFRelease(theUUID);
  return (__bridge NSString *)string;
}

@interface UNNetPGP_Tests : XCTestCase {

  UNNetPGP* pgp;
  NSFileManager* fm;
  NSString* plaintextFile;
  NSString* encodedFile;
  NSString* decodedFile;
  NSString* tmpDir;
}

@end

@implementation UNNetPGP_Tests

- (void)setUp
{
  [super setUp];
  
  fm = [NSFileManager defaultManager];

  pgp = [[UNNetPGP alloc] init];
  pgp.userId = @"alice@resturant.org";

  NSError* error = nil;
  NSArray* homeContents = [fm contentsOfDirectoryAtPath:pgp.homeDirectory error:&error];
  XCTAssertTrue(error == nil, @"error reading directory: %@", error.localizedDescription);

  for (NSString* item in homeContents) {
    NSString* itemPath = [pgp.homeDirectory stringByAppendingPathComponent:item];
    [fm removeItemAtPath:itemPath error:&error];
    XCTAssertTrue(error == nil, @"couldn't remove %@:\n%@", itemPath, error.localizedDescription);
  }
  
  NSString* newDir = [@"UUNetPGP_Tests" stringByAppendingPathComponent:getUUID()];
  tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:newDir];
  
  [fm createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:&error];
  if (![fm fileExistsAtPath:tmpDir] || error) {
    XCTFail(@"couldn't create tmpDir: %@", error.localizedDescription);
  }

  plaintextFile = [tmpDir stringByAppendingPathComponent:@"plain.txt"];
  encodedFile = [tmpDir stringByAppendingPathComponent:@"plain.txt.gpg"];
  decodedFile = [tmpDir stringByAppendingPathComponent:@"plain.decoded.txt"];
  
  NSData* plainData = [PLAINTEXT dataUsingEncoding:NSUTF8StringEncoding];
  [plainData writeToFile:plaintextFile atomically:YES];
  XCTAssertTrue([fm fileExistsAtPath:plaintextFile], @"expect file is present");
    
  // set home directory
  pgp.homeDirectory = [tmpDir stringByAppendingPathComponent:@"home"];
  [fm createDirectoryAtPath:pgp.homeDirectory withIntermediateDirectories:YES attributes:nil error:&error];
  if (![fm fileExistsAtPath:pgp.homeDirectory] || error) {
    XCTFail(@"couldn't create home directory: %@", error.localizedDescription);
  }
}

- (void)tearDown
{
  [super tearDown];

  NSError *error = nil;
  [fm removeItemAtPath:tmpDir error:&error];
  XCTAssertTrue(error == nil, @"couldn't remove %@:\n%@", tmpDir, error.localizedDescription);
}

- (void)testHomeDirectory
{
  NSString* home = [pgp homeDirectory];
  XCTAssertTrue(home != nil, @"home directory should not be nil");
  BOOL isDirectory = NO;
  BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:home isDirectory:&isDirectory];
  XCTAssertTrue(exists && isDirectory, @"home directory should exist");
}

- (void)testBasicGenerateKey
{
  BOOL generated = [pgp generateKey:1024];
  XCTAssertTrue(generated, @"key generation should be true");
}

- (void) testFileEncoding
{
  pgp.password = PASSWORD;
  pgp.armored  = YES;
  
  BOOL success = [pgp generateKey:1024];
  XCTAssertTrue(success, @"key generation should be true");
  
  // Encrypt
  success = [pgp encryptFileAtPath:plaintextFile toFileAtPath:encodedFile];
  XCTAssertTrue(success, @"encryption should report success");
  XCTAssertTrue([fm fileExistsAtPath:encodedFile], @"encrypted file should exist: %@", encodedFile);

  // Decrypt
  success = [pgp decryptFileAtPath:encodedFile toFileAtPath:decodedFile];
  XCTAssertTrue(success, @"decryption should report success");
  XCTAssertTrue([fm fileExistsAtPath:decodedFile], @"decrypted file should exist: %@", decodedFile);
  
  // Check result
  NSError* error = nil;
  NSString* decryptedText = [NSString stringWithContentsOfFile:decodedFile usedEncoding:nil error:&error];
  XCTAssertNil(error, @"don't expect an error: %@", error.localizedDescription);
  XCTAssertEqualObjects(PLAINTEXT, decryptedText, @"expect decrypted text to match original plaintext");
}

- (void) testDataEncoding
{
  pgp.password = PASSWORD;
  pgp.armored  = YES;
  
  BOOL success = [pgp generateKey:1024];
  XCTAssertTrue(success, @"key generation should be true");
  
  NSData *plainData = [NSData dataWithContentsOfFile:plaintextFile];
  
  // Encrypt
  NSData *encodedData = [pgp encryptData:plainData];
  XCTAssertNotNil(encodedData, @"encryption should success");
  
  // Decrypt
  NSData *decodedData = [pgp decryptData:encodedData];
  XCTAssertNotNil(decodedData, @"decryption should report success");
  
  // Check result
  XCTAssertEqualObjects(plainData, decodedData, @"expect decrypted data to match original plaintext");
}

- (void)testGenerateAndExportNamedKey {
  BOOL generated = [pgp generateKey:2048 named:@"alice" toDirectory:pgp.homeDirectory];
  XCTAssertTrue(generated, @"key generation for Alice should be true");
  
  NSString* keyString = [pgp exportKeyNamed:@"alice"];
  
  XCTAssertTrue([keyString hasPrefix:@"-----BEGIN PGP PUBLIC KEY BLOCK-----"], @"should begin properly instead of\n%@", keyString);
  
  // FAILS: There's extra junk after the end message
  // RFC 4880: Note that all these Armor Header Lines are to consist of a complete
  // line.  That is to say, there is always a line ending preceding the
  // starting five dashes, and following the ending five dashes.
  // XCTAssertTrue([keyString hasSuffix:@"-----END PGP PUBLIC KEY BLOCK-----"], @"should end properly insetad of\n%@", keyString);
}

- (void)testSignData {
  pgp.password = PASSWORD;
  pgp.armored = YES;
  
  BOOL success = [pgp generateKey:1024];
  XCTAssertTrue(success, @"key generation should be true");
  
  NSData* inData = [PLAINTEXT dataUsingEncoding:NSUTF8StringEncoding];
  NSData* signedData = [pgp signData:inData];
  
  XCTAssertNotNil(signedData, @"expect signed data");
  NSLog(@"%@",[[NSString alloc] initWithData:signedData encoding:NSUTF8StringEncoding]);
  
  success = [pgp verifyData:signedData];
  XCTAssertTrue(success, @"expect verification");
}

//- (void)testSignFile {
//  BOOL success = [pgp generateKey:1024];
//  XCTAssertTrue(success, @"key generation should be true");
//  
//  XCTAssertTrue([fm fileExistsAtPath:plaintextFile], @"expect the plaintext file");
//  
//  NSString* sigFile = [pgp.homeDirectory stringByAppendingPathComponent:@"signed.asc"];
//  XCTAssertFalse([fm fileExistsAtPath:sigFile], @"don't expect a signature yet");
//  success = [pgp signFileAtPath:plaintextFile writeSignatureToFile:sigFile detached:YES];
//  
//  // FAILS: returns false & doesn't create signed file.
//  XCTAssertTrue(success, @"expect successful signing");
//  XCTAssertTrue([fm fileExistsAtPath:sigFile], @"expect signature file %@", sigFile);
//  
//  success = [pgp verifyFileAtPath:sigFile];
//  XCTAssertTrue(success, @"expect successful verification");
//}

@end
