#import <UIKit/UIKit.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/SignalRecipient.h>

#import "ContactsManager.h"

#import "Toshi-Swift.h"

@interface ContactsManager ()

@property (nonnull, nonatomic, readonly) Yap *yap;

@property (nonatomic, strong) NSCache *cache;

@property (nonatomic, copy, readwrite) NSArray<TokenUser *> *tokenContacts;

@property (nonatomic, strong) YapDatabaseConnection *databaseConnection;

@end

@implementation ContactsManager

- (instancetype)init
{
    if (self = [super init]) {
        self.cache = [[NSCache alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(databaseChanged:) name:YapDatabaseModifiedNotification object:nil];
    }
    
    return self;
}

- (YapDatabaseConnection *)databaseConnection
{
    if (!_databaseConnection) {
        YapDatabase *dataBase = self.yap.database;
        _databaseConnection = dataBase.newConnection;
        [_databaseConnection beginLongLivedReadTransaction];
    }
    
    return _databaseConnection;
}

- (Yap *)yap
{
    return [Yap sharedInstance];
}

- (void)refreshContacts
{
    self.tokenContacts = nil;
}

- (void)databaseChanged:(NSNotification *)notification
{
    NSArray <NSNotification *> *notifications = [self.databaseConnection beginLongLivedReadTransaction];

   YapDatabaseViewConnection *viewConnection = [self.databaseConnection ext:TokenUser.viewExtensionName];
    BOOL hasChangesForCurrentView = [viewConnection hasChangesForNotifications:notifications];
    
    
    if (hasChangesForCurrentView) {
        self.tokenContacts = nil;
    }
}

+ (BOOL)name:(nonnull NSString *)nameString matchesQuery:(nonnull NSString *)queryString
{
    return YES;
}

- (nonnull NSString *)displayNameForPhoneIdentifier:(nullable NSString *)phoneNumber
{
    for (SignalAccount *account in self.signalAccounts) {
        Contact *contact = account.contact;
        if ([contact.userTextPhoneNumbers.firstObject isEqualToString:phoneNumber]) {
            return contact.firstName;
        }
    }

    return @"";
}

- (NSArray<TokenUser *> *)tokenContacts
{
    if (!_tokenContacts) {
        NSMutableArray <TokenUser *> *contacts = [NSMutableArray array];
        
        NSArray *contactsData = [self.yap retrieveObjectsIn:TokenUser.storedContactKey];
        for (NSData *contactData in contactsData) {
            NSDictionary<NSString *, id> *json = [NSJSONSerialization JSONObjectWithData:contactData options:0 error:0];
            TokenUser *tokenContact = [[TokenUser alloc] initWithJson:json shouldSave:NO];
            
            [contacts addObject:tokenContact];
        }
        
        _tokenContacts = contacts.copy;
    }
    
    return _tokenContacts;
}

- (nullable TokenUser *)tokenContactForAddress:(nullable NSString *)address
{
    if (!address) { return nil; }
    
    TokenUser *contact = [self.cache objectForKey:address];

    if (!contact) {
        NSUInteger index = [self.tokenContacts indexOfObjectWithOptions:NSEnumerationReverse
                                               passingTest:^(TokenUser *object, NSUInteger i, BOOL *stop) {
                                                   return [object.address isEqualToString:address];
                                               }];
        if (index != NSNotFound) {
            contact = self.tokenContacts[index];
            [self.cache setObject:contact forKey:address];
        }
    }

    return contact;
}

- (NSArray<SignalAccount *> *)signalAccounts
{
    NSMutableDictionary<NSString *, SignalAccount *> *signalAccountMap = [NSMutableDictionary dictionary];
    NSMutableArray<SignalAccount *> *signalAccounts = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSArray<SignalRecipient *> *> *contactIdToSignalRecipientsMap = [NSMutableDictionary dictionary];
    NSMutableArray<Contact *> *contacts = [NSMutableArray array];
    
    for (TokenUser *tokenContact in self.tokenContacts) {
        Contact *contact = [[Contact alloc] initWithContactWithFirstName:tokenContact.username andLastName:tokenContact.name andUserTextPhoneNumbers:@[tokenContact.address] andImage:nil andContactID:(int)tokenContact.hash];
        
        [contacts addObject:contact];
        
        contactIdToSignalRecipientsMap[contact.uniqueId] = @[[[SignalRecipient alloc] initWithTextSecureIdentifier:tokenContact.address relay:nil]];
    }
    
    for (Contact *contact in contacts) {
        NSArray<SignalRecipient *> *signalRecipients = contactIdToSignalRecipientsMap[contact.uniqueId];
        for (SignalRecipient *signalRecipient in [signalRecipients sortedArrayUsingSelector:@selector(compare:)]) {
            SignalAccount *signalAccount = [[SignalAccount alloc] initWithSignalRecipient:signalRecipient];
            signalAccount.contact = contact;
            if (signalRecipients.count > 1) {
                @throw NSInvalidArgumentException;
                
            }
            
            if (signalAccountMap[signalAccount.recipientId]) {
                NSLog(@"Ignoring duplicate contact: %@, %@", signalAccount.recipientId, contact.fullName);
                continue;
            }
            
            signalAccountMap[signalAccount.recipientId] = signalAccount;
            [signalAccounts addObject:signalAccount];
        }
    }
    
    return signalAccounts;
}

- (nullable UIImage *)imageForPhoneIdentifier:(nullable NSString *)phoneNumber
{
    TokenUser *contact = [self tokenContactForAddress:phoneNumber];

    return [AvatarManager.shared cachedAvatarFor:contact.avatarPath];
}

@end