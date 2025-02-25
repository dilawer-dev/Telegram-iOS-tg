import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI
import ItemListPeerActionItem
import AvatarNode

enum SelectivePrivacySettingsKind {
    case presence
    case groupInvitations
    case voiceCalls
    case profilePhoto
    case forwards
    case phoneNumber
    case voiceMessages
    case bio
}

private enum SelectivePrivacySettingType {
    case everybody
    case contacts
    case nobody
    
    init(_ setting: SelectivePrivacySettings) {
        switch setting {
            case .disableEveryone:
                self = .nobody
            case .enableContacts:
                self = .contacts
            case .enableEveryone:
                self = .everybody
        }
    }
}

enum SelectivePrivacySettingsPeerTarget {
    case main
    case callP2P
}

private final class SelectivePrivacySettingsControllerArguments {
    let context: AccountContext
    
    let updateType: (SelectivePrivacySettingType) -> Void
    let openSelective: (SelectivePrivacySettingsPeerTarget, Bool) -> Void
    
    let updateCallP2PMode: ((SelectivePrivacySettingType) -> Void)?
    let updateCallIntegrationEnabled: ((Bool) -> Void)?
    let updatePhoneDiscovery: ((Bool) -> Void)?
    let copyPhoneLink: ((String) -> Void)?
    let setPublicPhoto: (() -> Void)?
    let removePublicPhoto: (() -> Void)?
    let updateHideReadTime: ((Bool) -> Void)?
    let openPremiumIntro: () -> Void
    
    init(
        context: AccountContext,
        updateType: @escaping (SelectivePrivacySettingType) -> Void,
        openSelective: @escaping (SelectivePrivacySettingsPeerTarget, Bool) -> Void,
        updateCallP2PMode: ((SelectivePrivacySettingType) -> Void)?,
        updateCallIntegrationEnabled: ((Bool) -> Void)?,
        updatePhoneDiscovery: ((Bool) -> Void)?,
        copyPhoneLink: ((String) -> Void)?,
        setPublicPhoto: (() -> Void)?,
        removePublicPhoto: (() -> Void)?,
        updateHideReadTime: ((Bool) -> Void)?,
        openPremiumIntro: @escaping () -> Void
    ) {
        self.context = context
        self.updateType = updateType
        self.openSelective = openSelective
        self.updateCallP2PMode = updateCallP2PMode
        self.updateCallIntegrationEnabled = updateCallIntegrationEnabled
        self.updatePhoneDiscovery = updatePhoneDiscovery
        self.copyPhoneLink = copyPhoneLink
        self.setPublicPhoto = setPublicPhoto
        self.removePublicPhoto = removePublicPhoto
        self.updateHideReadTime = updateHideReadTime
        self.openPremiumIntro = openPremiumIntro
    }
}

private enum SelectivePrivacySettingsSection: Int32 {
    case forwards
    case setting
    case peers
    case callsP2P
    case callsP2PPeers
    case callsIntegrationEnabled
    case phoneDiscovery
    case photo
    case hideReadTime
    case premium
}

private func stringForUserCount(_ peers: [EnginePeer.Id: SelectivePrivacyPeer], strings: PresentationStrings) -> String {
    if peers.isEmpty {
        return strings.PrivacyLastSeenSettings_EmpryUsersPlaceholder
    } else {
        var result = 0
        for (_, peer) in peers {
            result += peer.userCount
        }
        return strings.UserCount(Int32(result))
    }
}

private enum SelectivePrivacySettingsEntry: ItemListNodeEntry {
    case forwardsPreviewHeader(PresentationTheme, String)
    case forwardsPreview(PresentationTheme, TelegramWallpaper, PresentationFontSize, PresentationChatBubbleCorners, PresentationStrings, PresentationDateTimeFormat, PresentationPersonNameOrder, String, Bool, String)
    case settingHeader(PresentationTheme, String)
    case everybody(PresentationTheme, String, Bool)
    case contacts(PresentationTheme, String, Bool)
    case nobody(PresentationTheme, String, Bool)
    case settingInfo(PresentationTheme, String, String)
    case exceptionsHeader(PresentationTheme, String)
    case disableFor(PresentationTheme, String, String)
    case enableFor(PresentationTheme, String, String)
    case peersInfo(PresentationTheme, String)
    case callsP2PHeader(PresentationTheme, String)
    case callsP2PAlways(PresentationTheme, String, Bool)
    case callsP2PContacts(PresentationTheme, String, Bool)
    case callsP2PNever(PresentationTheme, String, Bool)
    case callsP2PInfo(PresentationTheme, String)
    case callsP2PDisableFor(PresentationTheme, String, String)
    case callsP2PEnableFor(PresentationTheme, String, String)
    case callsP2PPeersInfo(PresentationTheme, String)
    case callsIntegrationEnabled(PresentationTheme, String, Bool)
    case callsIntegrationInfo(PresentationTheme, String)
    case phoneDiscoveryHeader(PresentationTheme, String)
    case phoneDiscoveryEverybody(PresentationTheme, String, Bool)
    case phoneDiscoveryMyContacts(PresentationTheme, String, Bool)
    case phoneDiscoveryInfo(PresentationTheme, String, String)
    case hideReadTime(PresentationTheme, String, Bool, Bool)
    case hideReadTimeInfo(PresentationTheme, String)
    case subscribeToPremium(PresentationTheme, String)
    case subscribeToPremiumInfo(PresentationTheme, String)
    case setPublicPhoto(PresentationTheme, String)
    case removePublicPhoto(PresentationTheme, String, EnginePeer, TelegramMediaImage?, UIImage?)
    case publicPhotoInfo(PresentationTheme, String)
    
    var section: ItemListSectionId {
        switch self {
            case .forwardsPreviewHeader, .forwardsPreview:
                return SelectivePrivacySettingsSection.forwards.rawValue
            case .settingHeader, .everybody, .contacts, .nobody, .settingInfo:
                return SelectivePrivacySettingsSection.setting.rawValue
            case .exceptionsHeader, .disableFor, .enableFor, .peersInfo:
                return SelectivePrivacySettingsSection.peers.rawValue
            case .callsP2PHeader, .callsP2PAlways, .callsP2PContacts, .callsP2PNever, .callsP2PInfo:
                return SelectivePrivacySettingsSection.callsP2P.rawValue
            case .callsP2PDisableFor, .callsP2PEnableFor, .callsP2PPeersInfo:
                return SelectivePrivacySettingsSection.callsP2PPeers.rawValue
            case .callsIntegrationEnabled, .callsIntegrationInfo:
                return SelectivePrivacySettingsSection.callsIntegrationEnabled.rawValue
            case .phoneDiscoveryHeader, .phoneDiscoveryEverybody, .phoneDiscoveryMyContacts, .phoneDiscoveryInfo:
                return SelectivePrivacySettingsSection.phoneDiscovery.rawValue
            case .setPublicPhoto, .removePublicPhoto, .publicPhotoInfo:
                return SelectivePrivacySettingsSection.photo.rawValue
            case .hideReadTime, .hideReadTimeInfo:
                return SelectivePrivacySettingsSection.hideReadTime.rawValue
            case .subscribeToPremium, .subscribeToPremiumInfo:
                return SelectivePrivacySettingsSection.premium.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
            case .forwardsPreviewHeader:
                return 0
            case .forwardsPreview:
                return 1
            case .settingHeader:
                return 2
            case .everybody:
                return 3
            case .contacts:
                return 4
            case .nobody:
                return 5
            case .settingInfo:
                return 6
            case .phoneDiscoveryHeader:
                return 7
            case .phoneDiscoveryEverybody:
                return 8
            case .phoneDiscoveryMyContacts:
                return 9
            case .phoneDiscoveryInfo:
                return 10
            case .exceptionsHeader:
                return 11
            case .disableFor:
                return 12
            case .enableFor:
                return 13
            case .peersInfo:
                return 14
            case .callsP2PHeader:
                return 15
            case .callsP2PAlways:
                return 16
            case .callsP2PContacts:
                return 17
            case .callsP2PNever:
                return 18
            case .callsP2PInfo:
                return 19
            case .callsP2PDisableFor:
                return 20
            case .callsP2PEnableFor:
                return 21
            case .callsP2PPeersInfo:
                return 22
            case .callsIntegrationEnabled:
                return 23
            case .callsIntegrationInfo:
                return 24
            case .setPublicPhoto:
                return 24
            case .removePublicPhoto:
                return 25
            case .publicPhotoInfo:
                return 26
            case .hideReadTime:
                return 27
            case .hideReadTimeInfo:
                return 28
            case .subscribeToPremium:
                return 29
            case .subscribeToPremiumInfo:
                return 30
        }
    }
    
    static func ==(lhs: SelectivePrivacySettingsEntry, rhs: SelectivePrivacySettingsEntry) -> Bool {
        switch lhs {
            case let .forwardsPreviewHeader(lhsTheme, lhsText):
                if case let .forwardsPreviewHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .forwardsPreview(lhsTheme, lhsWallpaper, lhsFontSize, lhsChatBubbleCorners, lhsStrings, lhsTimeFormat, lhsNameOrder, lhsPeerName, lhsLinkEnabled, lhsTooltipText):
                if case let .forwardsPreview(rhsTheme, rhsWallpaper, rhsFontSize, rhsChatBubbleCorners, rhsStrings, rhsTimeFormat, rhsNameOrder, rhsPeerName, rhsLinkEnabled, rhsTooltipText) = rhs, lhsTheme === rhsTheme, lhsWallpaper == rhsWallpaper, lhsFontSize == rhsFontSize, lhsChatBubbleCorners == rhsChatBubbleCorners, lhsStrings === rhsStrings, lhsTimeFormat == rhsTimeFormat, lhsNameOrder == rhsNameOrder, lhsPeerName == rhsPeerName, lhsLinkEnabled == rhsLinkEnabled, lhsTooltipText == rhsTooltipText {
                    return true
                } else {
                    return false
                }
            case let .settingHeader(lhsTheme, lhsText):
                if case let .settingHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .everybody(lhsTheme, lhsText, lhsValue):
                if case let .everybody(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .contacts(lhsTheme, lhsText, lhsValue):
                if case let .contacts(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .nobody(lhsTheme, lhsText, lhsValue):
                if case let .nobody(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .exceptionsHeader(lhsTheme, lhsText):
                if case let .exceptionsHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .settingInfo(lhsTheme, lhsText, lhsLink):
                if case let .settingInfo(rhsTheme, rhsText, rhsLink) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsLink == rhsLink {
                    return true
                } else {
                    return false
                }
            case let .disableFor(lhsTheme, lhsText, lhsValue):
                if case let .disableFor(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .enableFor(lhsTheme, lhsText, lhsValue):
                if case let .enableFor(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .peersInfo(lhsTheme, lhsText):
                if case let .peersInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .callsP2PHeader(lhsTheme, lhsText):
                if case let .callsP2PHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .callsP2PInfo(lhsTheme, lhsText):
                if case let .callsP2PInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .callsP2PAlways(lhsTheme, lhsText, lhsValue):
                if case let .callsP2PAlways(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .callsP2PContacts(lhsTheme, lhsText, lhsValue):
                if case let .callsP2PContacts(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .callsP2PNever(lhsTheme, lhsText, lhsValue):
                if case let .callsP2PNever(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .callsP2PDisableFor(lhsTheme, lhsText, lhsValue):
                if case let .callsP2PDisableFor(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .callsP2PEnableFor(lhsTheme, lhsText, lhsValue):
                if case let .callsP2PEnableFor(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .callsP2PPeersInfo(lhsTheme, lhsText):
                if case let .callsP2PPeersInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .callsIntegrationEnabled(lhsTheme, lhsText, lhsValue):
                if case let .callsIntegrationEnabled(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .callsIntegrationInfo(lhsTheme, lhsText):
                if case let .callsIntegrationInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .phoneDiscoveryHeader(lhsTheme, lhsText):
                if case let .phoneDiscoveryHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .phoneDiscoveryEverybody(lhsTheme, lhsText, lhsValue):
                if case let .phoneDiscoveryEverybody(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .phoneDiscoveryMyContacts(lhsTheme, lhsText, lhsValue):
                if case let .phoneDiscoveryMyContacts(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .phoneDiscoveryInfo(lhsTheme, lhsText, lhsLink):
                if case let .phoneDiscoveryInfo(rhsTheme, rhsText, rhsLink) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsLink == rhsLink {
                    return true
                } else {
                    return false
                }
            case let .setPublicPhoto(lhsTheme, lhsText):
                if case let .setPublicPhoto(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .removePublicPhoto(lhsTheme, lhsText, lhsPeer, lhsRep, lhsImage):
                if case let .removePublicPhoto(rhsTheme, rhsText, rhsPeer, rhsRep, rhsImage) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsPeer == rhsPeer, lhsRep == rhsRep, lhsImage === rhsImage {
                    return true
                } else {
                    return false
                }
            case let .publicPhotoInfo(lhsTheme, lhsText):
                if case let .publicPhotoInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .hideReadTime(lhsTheme, lhsText, lhsEnabled, lhsValue):
                if case let .hideReadTime(rhsTheme, rhsText, rhsEnabled, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsEnabled == rhsEnabled, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .hideReadTimeInfo(lhsTheme, lhsText):
                if case let .hideReadTimeInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .subscribeToPremium(lhsTheme, lhsText):
                if case let .subscribeToPremium(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .subscribeToPremiumInfo(lhsTheme, lhsText):
                if case let .subscribeToPremiumInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: SelectivePrivacySettingsEntry, rhs: SelectivePrivacySettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SelectivePrivacySettingsControllerArguments
        switch self {
            case let .forwardsPreviewHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, multiline: true, sectionId: self.section)
            case let .forwardsPreview(theme, wallpaper, fontSize, chatBubbleCorners, strings, dateTimeFormat, nameDisplayOrder, peerName, linkEnabled, tooltipText):
                return ForwardPrivacyChatPreviewItem(context: arguments.context, theme: theme, strings: strings, sectionId: self.section, fontSize: fontSize, chatBubbleCorners: chatBubbleCorners, wallpaper: wallpaper, dateTimeFormat: dateTimeFormat, nameDisplayOrder: nameDisplayOrder, peerName: peerName, linkEnabled: linkEnabled, tooltipText: tooltipText)
            case let .settingHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, multiline: true, sectionId: self.section)
            case let .everybody(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateType(.everybody)
                })
            case let .contacts(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateType(.contacts)
                })
            case let .nobody(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateType(.nobody)
                })
            case let .settingInfo(_, text, link):
                return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section, linkAction: { _ in
                    arguments.copyPhoneLink?(link)
                })
            case let .exceptionsHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .disableFor(_, title, value):
                return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                    arguments.openSelective(.main, false)
                })
            case let .enableFor(_, title, value):
                return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                    arguments.openSelective(.main, true)
                })
            case let .peersInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .callsP2PHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .callsP2PAlways(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateCallP2PMode?(.everybody)
                })
            case let .callsP2PContacts(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateCallP2PMode?(.contacts)
                })
            case let .callsP2PNever(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateCallP2PMode?(.nobody)
                })
            case let .callsP2PInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .callsP2PDisableFor(_, title, value):
                return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                    arguments.openSelective(.callP2P, false)
                })
            case let .callsP2PEnableFor(_, title, value):
                return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                    arguments.openSelective(.callP2P, true)
                })
            case let .callsP2PPeersInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .callsIntegrationEnabled(_, text, value):
                return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.updateCallIntegrationEnabled?(value)
                })
            case let .callsIntegrationInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .phoneDiscoveryHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .phoneDiscoveryEverybody(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updatePhoneDiscovery?(true)
                })
            case let .phoneDiscoveryMyContacts(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updatePhoneDiscovery?(false)
                })
            case let .phoneDiscoveryInfo(_, text, link):
                return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section, linkAction: { _ in
                    arguments.copyPhoneLink?(link)
                })
            case let .setPublicPhoto(theme, text):
                return ItemListPeerActionItem(presentationData: presentationData, icon: PresentationResourcesItemList.addPhotoIcon(theme), title: text, sectionId: self.section, height: .generic, color: .accent, editing: false, action: {
                    arguments.setPublicPhoto?()
                })
            case let .removePublicPhoto(_, text, peer, image, completeImage):
                return ItemListPeerActionItem(presentationData: presentationData, icon: completeImage, iconSignal: completeImage == nil ? peerAvatarCompleteImage(account: arguments.context.account, peer: peer, forceProvidedRepresentation: true, representation: image?.representationForDisplayAtSize(PixelDimensions(width: 28, height: 28)), size: CGSize(width: 28.0, height: 28.0)) : nil, title: text, sectionId: self.section, height: .generic, color: .destructive, editing: false, action: {
                    arguments.removePublicPhoto?()
                })
            case let .publicPhotoInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section, linkAction: { _ in
                })
            case let .hideReadTime(_, text, enabled, value):
                return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.updateHideReadTime?(value)
                })
            case let .hideReadTimeInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .subscribeToPremium(_, text):
                return ItemListPeerActionItem(presentationData: presentationData, icon: nil, title: text, sectionId: self.section, height: .generic, color: .accent, editing: false, action: {
                    arguments.openPremiumIntro()
                })
            case let .subscribeToPremiumInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct SelectivePrivacySettingsControllerState: Equatable {
    let setting: SelectivePrivacySettingType
    let enableFor: [EnginePeer.Id: SelectivePrivacyPeer]
    let disableFor: [EnginePeer.Id: SelectivePrivacyPeer]
    let enableForCloseFriends: Bool
    
    let saving: Bool
    
    let callDataSaving: VoiceCallDataSaving?
    let callP2PMode: SelectivePrivacySettingType?
    let callP2PEnableFor: [EnginePeer.Id: SelectivePrivacyPeer]?
    let callP2PDisableFor: [EnginePeer.Id: SelectivePrivacyPeer]?
    let callP2PEnableForCloseFriends: Bool?
    let callIntegrationAvailable: Bool?
    let callIntegrationEnabled: Bool?
    let phoneDiscoveryEnabled: Bool?
    let hideReadTimeEnabled: Bool?
    
    let uploadedPhoto: UIImage?
    
    init(setting: SelectivePrivacySettingType, enableFor: [EnginePeer.Id: SelectivePrivacyPeer], disableFor: [EnginePeer.Id: SelectivePrivacyPeer], enableForCloseFriends: Bool, saving: Bool, callDataSaving: VoiceCallDataSaving?, callP2PMode: SelectivePrivacySettingType?, callP2PEnableFor: [EnginePeer.Id: SelectivePrivacyPeer]?, callP2PDisableFor: [EnginePeer.Id: SelectivePrivacyPeer]?, callP2PEnableForCloseFriends: Bool?, callIntegrationAvailable: Bool?, callIntegrationEnabled: Bool?, phoneDiscoveryEnabled: Bool?, hideReadTimeEnabled: Bool?, uploadedPhoto: UIImage?) {
        self.setting = setting
        self.enableFor = enableFor
        self.disableFor = disableFor
        self.enableForCloseFriends = enableForCloseFriends
        self.saving = saving
        self.callDataSaving = callDataSaving
        self.callP2PMode = callP2PMode
        self.callP2PEnableFor = callP2PEnableFor
        self.callP2PDisableFor = callP2PDisableFor
        self.callP2PEnableForCloseFriends = callP2PEnableForCloseFriends
        self.callIntegrationAvailable = callIntegrationAvailable
        self.callIntegrationEnabled = callIntegrationEnabled
        self.phoneDiscoveryEnabled = phoneDiscoveryEnabled
        self.hideReadTimeEnabled = hideReadTimeEnabled
        self.uploadedPhoto = uploadedPhoto
    }
    
    static func ==(lhs: SelectivePrivacySettingsControllerState, rhs: SelectivePrivacySettingsControllerState) -> Bool {
        if lhs.setting != rhs.setting {
            return false
        }
        if lhs.enableFor != rhs.enableFor {
            return false
        }
        if lhs.disableFor != rhs.disableFor {
            return false
        }
        if lhs.enableForCloseFriends != rhs.enableForCloseFriends {
            return false
        }
        if lhs.saving != rhs.saving {
            return false
        }
        if lhs.callDataSaving != rhs.callDataSaving {
            return false
        }
        if lhs.callP2PMode != rhs.callP2PMode {
            return false
        }
        if lhs.callP2PEnableFor != rhs.callP2PEnableFor {
            return false
        }
        if lhs.callP2PDisableFor != rhs.callP2PDisableFor {
            return false
        }
        if lhs.callP2PEnableForCloseFriends != rhs.callP2PEnableForCloseFriends {
            return false
        }
        if lhs.callIntegrationAvailable != rhs.callIntegrationAvailable {
            return false
        }
        if lhs.callIntegrationEnabled != rhs.callIntegrationEnabled {
            return false
        }
        if lhs.phoneDiscoveryEnabled != rhs.phoneDiscoveryEnabled {
            return false
        }
        if lhs.hideReadTimeEnabled != rhs.hideReadTimeEnabled {
            return false
        }
        if lhs.uploadedPhoto !== rhs.uploadedPhoto {
            return false
        }
        
        return true
    }
    
    func withUpdatedSetting(_ setting: SelectivePrivacySettingType) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedEnableFor(_ enableFor: [EnginePeer.Id: SelectivePrivacyPeer]) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedDisableFor(_ disableFor: [EnginePeer.Id: SelectivePrivacyPeer]) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedEnableForCloseFriends(_ enableForCloseFriends: Bool) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedSaving(_ saving: Bool) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedCallP2PMode(_ mode: SelectivePrivacySettingType) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: mode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedCallP2PEnableFor(_ enableFor: [EnginePeer.Id: SelectivePrivacyPeer]) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: enableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedCallP2PDisableFor(_ disableFor: [EnginePeer.Id: SelectivePrivacyPeer]) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: disableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedCallP2PEnableForCloseFriends(_ callP2PEnableForCloseFriends: Bool) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedCallsIntegrationEnabled(_ enabled: Bool) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: enabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedPhoneDiscoveryEnabled(_ phoneDiscoveryEnabled: Bool) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
    func withUpdatedUploadedPhoto(_ uploadedPhoto: UIImage?) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: self.hideReadTimeEnabled, uploadedPhoto: uploadedPhoto)
    }
    
    func withUpdatedHideReadTimeEnabled(_ hideReadTimeEnabled: Bool) -> SelectivePrivacySettingsControllerState {
        return SelectivePrivacySettingsControllerState(setting: self.setting, enableFor: self.enableFor, disableFor: self.disableFor, enableForCloseFriends: self.enableForCloseFriends, saving: self.saving, callDataSaving: self.callDataSaving, callP2PMode: self.callP2PMode, callP2PEnableFor: self.callP2PEnableFor, callP2PDisableFor: self.callP2PDisableFor, callP2PEnableForCloseFriends: self.callP2PEnableForCloseFriends, callIntegrationAvailable: self.callIntegrationAvailable, callIntegrationEnabled: self.callIntegrationEnabled, phoneDiscoveryEnabled: self.phoneDiscoveryEnabled, hideReadTimeEnabled: hideReadTimeEnabled, uploadedPhoto: self.uploadedPhoto)
    }
    
}

private func selectivePrivacySettingsControllerEntries(presentationData: PresentationData, kind: SelectivePrivacySettingsKind, state: SelectivePrivacySettingsControllerState, peerName: String, phoneNumber: String, peer: EnginePeer?, publicPhoto: TelegramMediaImage?) -> [SelectivePrivacySettingsEntry] {
    var entries: [SelectivePrivacySettingsEntry] = []
    
    let settingTitle: String
    let settingInfoText: String?
    let disableForText: String
    let enableForText: String
    switch kind {
        case .presence:
            settingTitle = presentationData.strings.PrivacyLastSeenSettings_WhoCanSeeMyTimestamp
            settingInfoText = presentationData.strings.PrivacyLastSeenSettings_CustomHelp
            disableForText = presentationData.strings.PrivacyLastSeenSettings_NeverShareWith
            enableForText = presentationData.strings.PrivacyLastSeenSettings_AlwaysShareWith
        case .groupInvitations:
            settingTitle = presentationData.strings.Privacy_GroupsAndChannels_WhoCanAddMe
            settingInfoText = presentationData.strings.Privacy_GroupsAndChannels_CustomHelp
            disableForText = presentationData.strings.Privacy_GroupsAndChannels_NeverAllow
            enableForText = presentationData.strings.Privacy_GroupsAndChannels_AlwaysAllow
        case .voiceCalls:
            settingTitle = presentationData.strings.Privacy_Calls_WhoCanCallMe
            settingInfoText = presentationData.strings.Privacy_Calls_CustomHelp
            disableForText = presentationData.strings.Privacy_GroupsAndChannels_NeverAllow
            enableForText = presentationData.strings.Privacy_GroupsAndChannels_AlwaysAllow
        case .profilePhoto:
            settingTitle = presentationData.strings.Privacy_ProfilePhoto_WhoCanSeeMyPhoto
            settingInfoText = presentationData.strings.Privacy_ProfilePhoto_CustomHelp
            disableForText = presentationData.strings.PrivacyLastSeenSettings_NeverShareWith
            enableForText = presentationData.strings.PrivacyLastSeenSettings_AlwaysShareWith
        case .forwards:
            settingTitle = presentationData.strings.Privacy_Forwards_WhoCanForward
            settingInfoText = presentationData.strings.Privacy_Forwards_CustomHelp
            disableForText = presentationData.strings.Privacy_GroupsAndChannels_NeverAllow
            enableForText = presentationData.strings.Privacy_GroupsAndChannels_AlwaysAllow
        case .phoneNumber:
            settingTitle = presentationData.strings.PrivacyPhoneNumberSettings_WhoCanSeeMyPhoneNumber
            if state.setting == .nobody {
                settingInfoText = nil
            } else {
                settingInfoText = presentationData.strings.PrivacyPhoneNumberSettings_CustomPublicLink("+\(phoneNumber)").string
            }
            disableForText = presentationData.strings.PrivacyLastSeenSettings_NeverShareWith
            enableForText = presentationData.strings.PrivacyLastSeenSettings_AlwaysShareWith
        case .voiceMessages:
            settingTitle = presentationData.strings.Privacy_VoiceMessages_WhoCanSend
            settingInfoText = presentationData.strings.Privacy_VoiceMessages_CustomHelp
            disableForText = presentationData.strings.Privacy_GroupsAndChannels_NeverAllow
            enableForText = presentationData.strings.Privacy_GroupsAndChannels_AlwaysAllow
        case .bio:
            settingTitle = presentationData.strings.Privacy_Bio_WhoCanSeeMyBio
            settingInfoText = presentationData.strings.Privacy_Bio_CustomHelp
            disableForText = presentationData.strings.PrivacyLastSeenSettings_NeverShareWith
            enableForText = presentationData.strings.PrivacyLastSeenSettings_AlwaysShareWith
    }
    
    if case .forwards = kind {
        let linkEnabled: Bool
        let tootipText: String
        switch state.setting {
            case .everybody:
                tootipText = presentationData.strings.Privacy_Forwards_AlwaysLink
                linkEnabled = true
            case .contacts:
                tootipText = presentationData.strings.Privacy_Forwards_LinkIfAllowed
                linkEnabled = true
            case .nobody:
                tootipText = presentationData.strings.Privacy_Forwards_NeverLink
                linkEnabled = false
        }
        entries.append(.forwardsPreviewHeader(presentationData.theme, presentationData.strings.Privacy_Forwards_Preview))
        entries.append(.forwardsPreview(presentationData.theme, presentationData.chatWallpaper, presentationData.chatFontSize, presentationData.chatBubbleCorners, presentationData.strings, presentationData.dateTimeFormat, presentationData.nameDisplayOrder, peerName, linkEnabled, tootipText))
    }
    
    entries.append(.settingHeader(presentationData.theme, settingTitle))
    
    entries.append(.everybody(presentationData.theme, presentationData.strings.PrivacySettings_LastSeenEverybody, state.setting == .everybody))
    entries.append(.contacts(presentationData.theme, presentationData.strings.PrivacySettings_LastSeenContacts, state.setting == .contacts))
    entries.append(.nobody(presentationData.theme, presentationData.strings.PrivacySettings_LastSeenNobody, state.setting == .nobody))

    let phoneLink = "https://t.me/+\(phoneNumber)"
    if let settingInfoText = settingInfoText {
        entries.append(.settingInfo(presentationData.theme, settingInfoText, phoneLink))
    }
    
    if case .phoneNumber = kind, state.setting == .nobody {
        entries.append(.phoneDiscoveryHeader(presentationData.theme, presentationData.strings.PrivacyPhoneNumberSettings_DiscoveryHeader))
        entries.append(.phoneDiscoveryEverybody(presentationData.theme, presentationData.strings.PrivacySettings_LastSeenEverybody, state.phoneDiscoveryEnabled != false))
        entries.append(.phoneDiscoveryMyContacts(presentationData.theme, presentationData.strings.PrivacySettings_LastSeenContacts, state.phoneDiscoveryEnabled == false))
        entries.append(.phoneDiscoveryInfo(presentationData.theme, state.phoneDiscoveryEnabled != false ? presentationData.strings.PrivacyPhoneNumberSettings_CustomPublicLink("+\(phoneNumber)").string : presentationData.strings.PrivacyPhoneNumberSettings_CustomDisabledHelp, phoneLink))
    }
        
    entries.append(.exceptionsHeader(presentationData.theme, presentationData.strings.GroupInfo_Permissions_Exceptions))
    
    switch state.setting {
        case .everybody:
            entries.append(.disableFor(presentationData.theme, disableForText, stringForUserCount(state.disableFor, strings: presentationData.strings)))
        case .contacts:
            entries.append(.disableFor(presentationData.theme, disableForText, stringForUserCount(state.disableFor, strings: presentationData.strings)))
            entries.append(.enableFor(presentationData.theme, enableForText, stringForUserCount(state.enableFor, strings: presentationData.strings)))
        case .nobody:
            entries.append(.enableFor(presentationData.theme, enableForText, stringForUserCount(state.enableFor, strings: presentationData.strings)))
    }
    let exceptionsInfo: String
    if case .profilePhoto = kind {
        switch state.setting {
        case .nobody:
            exceptionsInfo = presentationData.strings.Privacy_ProfilePhoto_CustomOverrideAddInfo
        case .contacts:
            exceptionsInfo = presentationData.strings.Privacy_ProfilePhoto_CustomOverrideBothInfo
        case .everybody:
            exceptionsInfo = presentationData.strings.Privacy_ProfilePhoto_CustomOverrideInfo
        }
    } else {
        exceptionsInfo = presentationData.strings.PrivacyLastSeenSettings_CustomShareSettingsHelp
    }
    entries.append(.peersInfo(presentationData.theme, exceptionsInfo))
    
    if case .voiceCalls = kind, let p2pMode = state.callP2PMode, let integrationAvailable = state.callIntegrationAvailable, let integrationEnabled = state.callIntegrationEnabled  {
        entries.append(.callsP2PHeader(presentationData.theme, presentationData.strings.Privacy_Calls_P2P.uppercased()))
        
        entries.append(.callsP2PAlways(presentationData.theme, presentationData.strings.Privacy_Calls_P2PAlways, p2pMode == .everybody))
        entries.append(.callsP2PContacts(presentationData.theme, presentationData.strings.Privacy_Calls_P2PContacts, p2pMode == .contacts))
        entries.append(.callsP2PNever(presentationData.theme, presentationData.strings.Privacy_Calls_P2PNever, p2pMode == .nobody))
        entries.append(.callsP2PInfo(presentationData.theme, presentationData.strings.Privacy_Calls_P2PHelp))
        
        if let callP2PMode = state.callP2PMode, let disableFor = state.callP2PDisableFor, let enableFor = state.callP2PEnableFor {
            switch callP2PMode {
                case .everybody:
                    entries.append(.callsP2PDisableFor(presentationData.theme, disableForText, stringForUserCount(disableFor, strings: presentationData.strings)))
                case .contacts:
                    entries.append(.callsP2PDisableFor(presentationData.theme, disableForText, stringForUserCount(disableFor, strings: presentationData.strings)))
                    entries.append(.callsP2PEnableFor(presentationData.theme, enableForText, stringForUserCount(enableFor, strings: presentationData.strings)))
                case .nobody:
                    entries.append(.callsP2PEnableFor(presentationData.theme, enableForText, stringForUserCount(enableFor, strings: presentationData.strings)))
            }
        }
        entries.append(.callsP2PPeersInfo(presentationData.theme, presentationData.strings.PrivacyLastSeenSettings_CustomShareSettingsHelp))
        
        if integrationAvailable {
            entries.append(.callsIntegrationEnabled(presentationData.theme, presentationData.strings.Privacy_Calls_Integration, integrationEnabled))
            entries.append(.callsIntegrationInfo(presentationData.theme, presentationData.strings.Privacy_Calls_IntegrationHelp))
        }
    }
    
    if case .profilePhoto = kind, let peer = peer, state.setting != .everybody || !state.disableFor.isEmpty {
        if let publicPhoto = publicPhoto {
            entries.append(.setPublicPhoto(presentationData.theme, presentationData.strings.Privacy_ProfilePhoto_UpdatePublicPhoto))
            entries.append(.removePublicPhoto(presentationData.theme, !publicPhoto.videoRepresentations.isEmpty ? presentationData.strings.Privacy_ProfilePhoto_RemovePublicVideo : presentationData.strings.Privacy_ProfilePhoto_RemovePublicPhoto, peer, publicPhoto, state.uploadedPhoto))
        } else {
            entries.append(.setPublicPhoto(presentationData.theme, presentationData.strings.Privacy_ProfilePhoto_SetPublicPhoto))
        }
        entries.append(.publicPhotoInfo(presentationData.theme, presentationData.strings.Privacy_ProfilePhoto_PublicPhotoInfo))
    }
    
    if case .presence = kind, let peer {
        let isEnabled: Bool
        switch state.setting {
        case .everybody:
            if !state.disableFor.isEmpty {
                isEnabled = true
            } else {
                isEnabled = false
            }
        default:
            isEnabled = true
        }
        if isEnabled {
            entries.append(.hideReadTime(presentationData.theme, presentationData.strings.Settings_Privacy_ReadTime, isEnabled,  isEnabled && state.hideReadTimeEnabled == true))
            entries.append(.hideReadTimeInfo(presentationData.theme, presentationData.strings.Settings_Privacy_ReadTimeFooter))
            
            if !peer.isPremium {
                entries.append(.subscribeToPremium(presentationData.theme, presentationData.strings.Settings_Privacy_ReadTimePremium))
                entries.append(.subscribeToPremiumInfo(presentationData.theme, presentationData.strings.Settings_Privacy_ReadTimePremiumFooter))
            }
        }
    }
    
    return entries
}

func selectivePrivacySettingsController(
    context: AccountContext,
    kind: SelectivePrivacySettingsKind,
    current: SelectivePrivacySettings,
    callSettings: (SelectivePrivacySettings, VoiceCallSettings)? = nil,
    phoneDiscoveryEnabled: Bool? = nil,
    voipConfiguration: VoipConfiguration? = nil,
    callIntegrationAvailable: Bool? = nil,
    globalSettings: GlobalPrivacySettings? = nil,
    requestPublicPhotoSetup: ((@escaping (UIImage?) -> Void) -> Void)? = nil,
    requestPublicPhotoRemove: ((@escaping () -> Void) -> Void)? = nil,
    updated: @escaping (SelectivePrivacySettings, (SelectivePrivacySettings, VoiceCallSettings)?, Bool?, GlobalPrivacySettings?) -> Void
) -> ViewController {
    let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
    
    var initialEnableFor: [EnginePeer.Id: SelectivePrivacyPeer] = [:]
    var initialDisableFor: [EnginePeer.Id: SelectivePrivacyPeer] = [:]
    var initialEnableForCloseFriends = false
    switch current {
        case let .disableEveryone(enableFor, enableForCloseFriends):
            initialEnableFor = enableFor
            initialEnableForCloseFriends = enableForCloseFriends
        case let .enableContacts(enableFor, disableFor):
            initialEnableFor = enableFor
            initialDisableFor = disableFor
        case let .enableEveryone(disableFor):
            initialDisableFor = disableFor
    }
    var initialCallP2PEnableFor: [EnginePeer.Id: SelectivePrivacyPeer]?
    var initialCallP2PDisableFor: [EnginePeer.Id: SelectivePrivacyPeer]?
    var initialCallEnableForCloseFriends = false
    if let callCurrent = callSettings?.0 {
        switch callCurrent {
            case let .disableEveryone(enableFor, enableForCloseFriends):
                initialCallP2PEnableFor = enableFor
                initialCallP2PDisableFor = [:]
                initialCallEnableForCloseFriends = enableForCloseFriends
            case let .enableContacts(enableFor, disableFor):
                initialCallP2PEnableFor = enableFor
                initialCallP2PDisableFor = disableFor
            case let .enableEveryone(disableFor):
                initialCallP2PEnableFor = [:]
                initialCallP2PDisableFor = disableFor
        }
    }
    
    //TODO:replace hideReadTimeEnabled with actual value
    let initialState = SelectivePrivacySettingsControllerState(setting: SelectivePrivacySettingType(current), enableFor: initialEnableFor, disableFor: initialDisableFor, enableForCloseFriends: initialEnableForCloseFriends, saving: false, callDataSaving: callSettings?.1.dataSaving, callP2PMode: callSettings != nil ? SelectivePrivacySettingType(callSettings!.0) : nil, callP2PEnableFor: initialCallP2PEnableFor, callP2PDisableFor: initialCallP2PDisableFor, callP2PEnableForCloseFriends: initialCallEnableForCloseFriends, callIntegrationAvailable: callIntegrationAvailable, callIntegrationEnabled: callSettings?.1.enableSystemIntegration, phoneDiscoveryEnabled: phoneDiscoveryEnabled, hideReadTimeEnabled: globalSettings?.hideReadTime, uploadedPhoto: nil)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((SelectivePrivacySettingsControllerState) -> SelectivePrivacySettingsControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    var pushControllerImpl: ((ViewController, Bool) -> Void)?
    var presentControllerImpl: ((ViewController, Any?) -> Void)?
    
    let actionsDisposable = DisposableSet()
    
    let addPeerDisposable = MetaDisposable()
    actionsDisposable.add(addPeerDisposable)
    
    let arguments = SelectivePrivacySettingsControllerArguments(context: context, updateType: { type in
        updateState {
            $0.withUpdatedSetting(type)
        }
    }, openSelective: { target, enable in
        let title: String
        if enable {
            switch kind {
                case .presence:
                    title = strings.PrivacyLastSeenSettings_AlwaysShareWith_Title
                case .groupInvitations:
                    title = strings.Privacy_GroupsAndChannels_AlwaysAllow_Title
                case .voiceCalls:
                    title = strings.Privacy_Calls_AlwaysAllow_Title
                case .profilePhoto:
                    title = strings.Privacy_ProfilePhoto_AlwaysShareWith_Title
                case .forwards:
                    title = strings.Privacy_Forwards_AlwaysAllow_Title
                case .phoneNumber:
                    title = strings.PrivacyLastSeenSettings_AlwaysShareWith_Title
                case .voiceMessages:
                    title = strings.Privacy_VoiceMessages_AlwaysAllow_Title
                case .bio:
                    title = strings.Privacy_Bio_AlwaysShareWith_Title
            }
        } else {
            switch kind {
                case .presence:
                    title = strings.PrivacyLastSeenSettings_NeverShareWith_Title
                case .groupInvitations:
                    title = strings.Privacy_GroupsAndChannels_NeverAllow_Title
                case .voiceCalls:
                    title = strings.Privacy_Calls_NeverAllow_Title
                case .profilePhoto:
                    title = strings.Privacy_ProfilePhoto_NeverShareWith_Title
                case .forwards:
                    title = strings.Privacy_Forwards_NeverAllow_Title
                case .phoneNumber:
                    title = strings.PrivacyLastSeenSettings_NeverShareWith_Title
                case .voiceMessages:
                    title = strings.Privacy_VoiceMessages_NeverAllow_Title
                case .bio:
                    title = strings.Privacy_Bio_NeverShareWith_Title
            }
        }
        var peerIds: [EnginePeer.Id: SelectivePrivacyPeer] = [:]
        updateState { state in
            if enable {
                switch target {
                    case .main:
                        peerIds = state.enableFor
                    case .callP2P:
                        if let callP2PEnableFor = state.callP2PEnableFor {
                            peerIds = callP2PEnableFor
                        }
                }
            } else {
                switch target {
                    case .main:
                        peerIds = state.disableFor
                    case .callP2P:
                        if let callP2PDisableFor = state.callP2PDisableFor {
                            peerIds = callP2PDisableFor
                        }
                }
            }
            return state
        }
        if peerIds.isEmpty {
            let controller = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .peerSelection(searchChatList: true, searchGroups: true, searchChannels: false), options: []))
            addPeerDisposable.set((controller.result
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak controller] result in
                var peerIds: [ContactListPeerId] = []
                if case let .result(peerIdsValue, _) = result {
                    peerIds = peerIdsValue
                }
                
                if peerIds.isEmpty {
                    controller?.dismiss()
                    return
                }
                let filteredIds = peerIds.compactMap { peerId -> EnginePeer.Id? in
                    if case let .peer(value) = peerId {
                        return value
                    } else {
                        return nil
                    }
                }
                
                let _ = (context.engine.data.get(
                    EngineDataMap(filteredIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)),
                    EngineDataMap(filteredIds.map(TelegramEngine.EngineData.Item.Peer.ParticipantCount.init))
                )
                |> map { peerMap, participantCountMap -> [EnginePeer.Id: SelectivePrivacyPeer] in
                    var updatedPeers: [EnginePeer.Id: SelectivePrivacyPeer] = [:]
                    var existingIds = Set(updatedPeers.values.map { $0.peer.id })
                    for peerId in peerIds {
                        guard case let .peer(peerId) = peerId else {
                            continue
                        }
                        if let maybePeer = peerMap[peerId], let peer = maybePeer, !existingIds.contains(peerId) {
                            existingIds.insert(peerId)
                            var participantCount: Int32?
                            if case let .channel(channel) = peer, case .group = channel.info {
                                if let maybeParticipantCount = participantCountMap[peerId], let participantCountValue = maybeParticipantCount {
                                    participantCount = Int32(participantCountValue)
                                }
                            }
                            
                            updatedPeers[peer.id] = SelectivePrivacyPeer(peer: peer._asPeer(), participantCount: participantCount)
                        }
                    }
                    return updatedPeers
                }
                |> deliverOnMainQueue).start(next: { updatedPeerIds in
                    controller?.dismiss()
                    
                    updateState { state in
                        let state = state
                        if enable {
                            switch target {
                                case .main:
                                    var disableFor = state.disableFor
                                    for (key, _) in updatedPeerIds {
                                        disableFor.removeValue(forKey: key)
                                    }
                                    return state.withUpdatedEnableFor(updatedPeerIds).withUpdatedDisableFor(disableFor)
                                case .callP2P:
                                    var callP2PDisableFor = state.callP2PDisableFor ?? [:]
                                    for (key, _) in updatedPeerIds {
                                        callP2PDisableFor.removeValue(forKey: key)
                                    }
                                    return state.withUpdatedCallP2PEnableFor(updatedPeerIds).withUpdatedCallP2PDisableFor(callP2PDisableFor)
                            }
                        } else {
                            switch target {
                                case .main:
                                    var enableFor = state.enableFor
                                    for (key, _) in updatedPeerIds {
                                        enableFor.removeValue(forKey: key)
                                    }
                                    return state.withUpdatedDisableFor(updatedPeerIds).withUpdatedEnableFor(enableFor)
                                case .callP2P:
                                    var callP2PEnableFor = state.callP2PEnableFor ?? [:]
                                    for (key, _) in updatedPeerIds {
                                        callP2PEnableFor.removeValue(forKey: key)
                                    }
                                    return state.withUpdatedCallP2PDisableFor(updatedPeerIds).withUpdatedCallP2PEnableFor(callP2PEnableFor)
                            }
                        }
                    }
                })
            }))
            presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        } else {
            let controller = selectivePrivacyPeersController(context: context, title: title, initialPeers: peerIds, updated: { updatedPeerIds in
                updateState { state in
                    if enable {
                        switch target {
                            case .main:
                                var disableFor = state.disableFor
                                for (key, _) in updatedPeerIds {
                                    disableFor.removeValue(forKey: key)
                                }
                                return state.withUpdatedEnableFor(updatedPeerIds).withUpdatedDisableFor(disableFor)
                            case .callP2P:
                                var callP2PDisableFor = state.callP2PDisableFor ?? [:]
                                for (key, _) in updatedPeerIds {
                                    callP2PDisableFor.removeValue(forKey: key)
                                }
                                return state.withUpdatedCallP2PEnableFor(updatedPeerIds).withUpdatedCallP2PDisableFor(callP2PDisableFor)
                        }
                    } else {
                        switch target {
                            case .main:
                                var enableFor = state.enableFor
                                for (key, _) in updatedPeerIds {
                                    enableFor.removeValue(forKey: key)
                                }
                                return state.withUpdatedDisableFor(updatedPeerIds).withUpdatedEnableFor(enableFor)
                            case .callP2P:
                                var callP2PEnableFor = state.callP2PEnableFor ?? [:]
                                for (key, _) in updatedPeerIds {
                                    callP2PEnableFor.removeValue(forKey: key)
                                }
                                return state.withUpdatedCallP2PDisableFor(updatedPeerIds).withUpdatedCallP2PEnableFor(callP2PEnableFor)
                        }
                    }
                }
            })
            pushControllerImpl?(controller, true)
        }
    }, updateCallP2PMode: { mode in
        updateState { state in
            return state.withUpdatedCallP2PMode(mode)
        }
    }, updateCallIntegrationEnabled: { enabled in
        updateState { state in
            return state.withUpdatedCallsIntegrationEnabled(enabled)
        }
        let _ = updateVoiceCallSettingsSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            var settings = settings
            settings.enableSystemIntegration = enabled
            return settings
        }).start()
    }, updatePhoneDiscovery: { value in
        updateState { state in
            return state.withUpdatedPhoneDiscoveryEnabled(value)
        }
    }, copyPhoneLink: { link in
        UIPasteboard.general.string = link
        
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .linkCopied(text: strings.Conversation_LinkCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
    }, setPublicPhoto: {
        requestPublicPhotoSetup?({ result in
            var result = result
            if let image = result {
                result = generateImage(CGSize(width: 28.0, height: 28.0), contextGenerator: { size, context in
                    context.clear(CGRect(origin: .zero, size: size))
                    context.addPath(CGPath(ellipseIn: CGRect(origin: .zero, size: size), transform: nil))
                    context.clip()
                    if let cgImage = image.cgImage {
                        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
                    }
                }, opaque: false)
            }
            updateState { state in
                return state.withUpdatedUploadedPhoto(result)
            }
        })
    }, removePublicPhoto: {
        requestPublicPhotoRemove?({
            updateState { state in
                return state.withUpdatedUploadedPhoto(nil)
            }
        })
    }, updateHideReadTime: { value in
        updateState { state in
            return state.withUpdatedHideReadTimeEnabled(value)
        }
    }, openPremiumIntro: {
        let controller = context.sharedContext.makePremiumIntroController(context: context, source: .presence, forceDark: false, dismissed: nil)
        pushControllerImpl?(controller, true)
    })
    
    let peer = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
    let publicPhoto = context.account.postbox.peerView(id: context.account.peerId)
    |> map { view -> TelegramMediaImage? in
        if let cachedUserData = view.cachedData as? CachedUserData, case let .known(photo) = cachedUserData.fallbackPhoto {
            return photo
        } else {
            return nil
        }
    }
    
    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get(),
        peer,
        publicPhoto
    ) |> deliverOnMainQueue
    |> map { presentationData, state, peer, publicPhoto -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let peerName = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        var phoneNumber = ""
        if case let .user(user) = peer {
            phoneNumber = user.phone ?? ""
        }
        
        let title: String
        switch kind {
            case .presence:
                title = presentationData.strings.PrivacySettings_LastSeenTitle
            case .groupInvitations:
                title = presentationData.strings.Privacy_GroupsAndChannels
            case .voiceCalls:
                title = presentationData.strings.Settings_CallSettings
            case .profilePhoto:
                title = presentationData.strings.Privacy_ProfilePhoto
            case .forwards:
                title = presentationData.strings.Privacy_Forwards
            case .phoneNumber:
                title = presentationData.strings.Privacy_PhoneNumber
            case .voiceMessages:
                title = presentationData.strings.Privacy_VoiceMessages
            case .bio:
                title = presentationData.strings.Privacy_Bio
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: selectivePrivacySettingsControllerEntries(presentationData: presentationData, kind: kind, state: state, peerName: peerName ?? "", phoneNumber: phoneNumber, peer: peer, publicPhoto: publicPhoto), style: .blocks, animateChanges: true)
        
        return (controllerState, (listState, arguments))
    } |> afterDisposed {
        actionsDisposable.dispose()
    }
    
    struct AppliedSettings: Equatable {
        let settings: SelectivePrivacySettings
        let callP2PSettings: SelectivePrivacySettings?
        let callDataSaving: VoiceCallDataSaving?
        let callIntegrationEnabled: Bool?
        let phoneDiscoveryEnabled: Bool?
        let hideReadTimeEnabled: Bool?
    }
    
    var appliedSettings: AppliedSettings?
    
    let update: (Bool) -> Void = { save in
        var wasSaving = false
        var settings: SelectivePrivacySettings?
        var callP2PSettings: SelectivePrivacySettings?
        var phoneDiscoveryEnabled: Bool?
        var callDataSaving: VoiceCallDataSaving?
        var callIntegrationEnabled: Bool?
        var hideReadTimeEnabled: Bool?
        
        updateState { state in
            wasSaving = state.saving
            callDataSaving = state.callDataSaving
            callIntegrationEnabled = state.callIntegrationEnabled
            switch state.setting {
                case .everybody:
                    settings = SelectivePrivacySettings.enableEveryone(disableFor: state.disableFor)
                case .contacts:
                    settings = SelectivePrivacySettings.enableContacts(enableFor: state.enableFor, disableFor: state.disableFor)
                case .nobody:
                    settings = SelectivePrivacySettings.disableEveryone(enableFor: state.enableFor, enableForCloseFriends: state.enableForCloseFriends)
            }
            
            if case .phoneNumber = kind, let value = state.phoneDiscoveryEnabled {
                phoneDiscoveryEnabled = value
            }
            
            if case .presence = kind, let value = state.hideReadTimeEnabled {
                hideReadTimeEnabled = value
            }
            
            if case .voiceCalls = kind, let callP2PMode = state.callP2PMode, let disableFor = state.callP2PDisableFor, let enableFor = state.callP2PEnableFor, let enableForCloseFriends = state.callP2PEnableForCloseFriends {
                switch callP2PMode {
                    case .everybody:
                        callP2PSettings = SelectivePrivacySettings.enableEveryone(disableFor: disableFor)
                    case .contacts:
                        callP2PSettings = SelectivePrivacySettings.enableContacts(enableFor: enableFor, disableFor: disableFor)
                    case .nobody:
                        callP2PSettings = SelectivePrivacySettings.disableEveryone(enableFor: enableFor, enableForCloseFriends: enableForCloseFriends)
                }
            }
            
            return state.withUpdatedSaving(true)
        }
        
        if let settings = settings, !wasSaving {
            let settingsToApply = AppliedSettings(settings: settings, callP2PSettings: callP2PSettings, callDataSaving: callDataSaving, callIntegrationEnabled: callIntegrationEnabled, phoneDiscoveryEnabled: phoneDiscoveryEnabled, hideReadTimeEnabled: hideReadTimeEnabled)
            if appliedSettings == settingsToApply {
                return
            }
            appliedSettings = settingsToApply
            
            let type: UpdateSelectiveAccountPrivacySettingsType
            switch kind {
                case .presence:
                    type = .presence
                case .groupInvitations:
                    type = .groupInvitations
                case .voiceCalls:
                    type = .voiceCalls
                case .profilePhoto:
                    type = .profilePhoto
                case .forwards:
                    type = .forwards
                case .phoneNumber:
                    type = .phoneNumber
                case .voiceMessages:
                    type = .voiceMessages
                case .bio:
                    type = .bio
            }
            
            let updateSettingsSignal = context.engine.privacy.updateSelectiveAccountPrivacySettings(type: type, settings: settings)
            var updateCallP2PSettingsSignal: Signal<Void, NoError> = Signal.complete()
            if let callP2PSettings = callP2PSettings {
                updateCallP2PSettingsSignal = context.engine.privacy.updateSelectiveAccountPrivacySettings(type: .voiceCallsP2P, settings: callP2PSettings)
            }
            var updatePhoneDiscoverySignal: Signal<Void, NoError> = Signal.complete()
            if let phoneDiscoveryEnabled = phoneDiscoveryEnabled {
                updatePhoneDiscoverySignal = context.engine.privacy.updatePhoneNumberDiscovery(value: phoneDiscoveryEnabled)
            }
            
            var updateGlobalSettingsSignal: Signal<Never, NoError> = Signal.complete()
            var updatedGlobalSettings: GlobalPrivacySettings?
            if let _ = arguments.updateHideReadTime, let globalSettings {
                updatedGlobalSettings = GlobalPrivacySettings(automaticallyArchiveAndMuteNonContacts: globalSettings.automaticallyArchiveAndMuteNonContacts, keepArchivedUnmuted: globalSettings.keepArchivedUnmuted, keepArchivedFolders: globalSettings.keepArchivedFolders, hideReadTime: hideReadTimeEnabled ?? globalSettings.hideReadTime, nonContactChatsRequirePremium: globalSettings.nonContactChatsRequirePremium)
                if let updatedGlobalSettings {
                    updateGlobalSettingsSignal = context.engine.privacy.updateGlobalPrivacySettings(settings: updatedGlobalSettings)
                }
            }
            
            let _ = (combineLatest(updateSettingsSignal, updateCallP2PSettingsSignal, updatePhoneDiscoverySignal, updateGlobalSettingsSignal)
            |> deliverOnMainQueue).start(completed: {
            })
            
            if case .presence = kind {
                updated(settings, nil, phoneDiscoveryEnabled, updatedGlobalSettings)
            } else if case .voiceCalls = kind, let dataSaving = callDataSaving, let callP2PSettings = callP2PSettings, let systemIntegrationEnabled = callIntegrationEnabled {
                updated(settings, (callP2PSettings, VoiceCallSettings(dataSaving: dataSaving, enableSystemIntegration: systemIntegrationEnabled)), phoneDiscoveryEnabled, nil)
            } else {
                updated(settings, nil, phoneDiscoveryEnabled, nil)
            }
        }
    }
    
    let controller = ItemListController(context: context, state: signal)
    controller.willDisappear = { [weak controller] _ in
        if let controller = controller, let navigationController = controller.navigationController {
            let index = navigationController.viewControllers.firstIndex(of: controller)
            if index == nil || index == navigationController.viewControllers.count - 1 {
                update(true)
            }
        }
    }
    controller.didDisappear = { [weak controller] _ in
        if let controller = controller, controller.navigationController?.viewControllers.firstIndex(of: controller) == nil {
            //update(true)
        }
    }
    
    pushControllerImpl = { [weak controller] c, animated in
        (controller?.navigationController as? NavigationController)?.pushViewController(c, animated: animated)
    }
    presentControllerImpl = { [weak controller] c, a in
        if c is UndoOverlayController {
            controller?.forEachController { other in
                if let other = other as? UndoOverlayController {
                    other.dismiss()
                }
                return true
            }
            
            controller?.present(c, in: .current, with: a)
        } else {
            controller?.present(c, in: .window(.root), with: a)
        }
    }
    
    return controller
}
