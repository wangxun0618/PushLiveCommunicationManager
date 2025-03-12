//
//  XMPushLiveCommunicationManager.swift
//
//
//  Created by M2-2023 on 2025/3/10.
//  Copyright © 2025 User. All rights reserved.
//

import UIKit
import LiveCommunicationKit
import PushKit
import AVFAudio

@available(iOS 17.4, *)
class XMPushLiveCommunicationManager: NSObject {
    @objc
    static let shareInstance = XMPushLiveCommunicationManager()
    
    var pushRegistry: PKPushRegistry?
    
    lazy var lckManager: ConversationManager = {
        let iconTemplateImageData = UIImage(named: "AppIcon")?.jpegData(compressionQuality: 1)
        let manager = ConversationManager.init(configuration: .init(
            ringtoneName: nil,
            iconTemplateImageData: iconTemplateImageData,
            maximumConversationGroups: 1,
            maximumConversationsPerConversationGroup: 1,
            includesConversationInRecents: false,
            supportsVideo: false,
            supportedHandleTypes: [.generic]
        ))
        manager.delegate = self
        return manager
    }()
    
    var dictionaryPayload: [AnyHashable : Any]?
    
    @objc
    var didUpdateDeviceTokenClosure: ((String)->Void)?

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private override init() {
        super.init()
        registerPushKit()
    }
    
    
    private func registerPushKit() {

        self.pushRegistry = PKPushRegistry(queue: DispatchQueue.global())
        self.pushRegistry?.delegate = self
        self.pushRegistry?.desiredPushTypes = [.voIP]
        
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(handleRouteChange),
                                             name: AVAudioSession.routeChangeNotification,
                                             object: nil)
    }
    
    func reportNewIncomingConversation(payload: [AnyHashable : Any]) {
        
        self.dictionaryPayload = payload

        let semaphore = DispatchSemaphore(value: 0)
        Task  { @MainActor in
            do {
                let custom_data = payload["custom_data"] as? [AnyHashable : Any]
                let nickname = (custom_data?["nickname"] as? String) ?? ""
                var update = Conversation.Update(members: [Handle(type: .generic, value:nickname, displayName: nickname)])
                update.capabilities = .playingTones
                let uuid = UUID()

                try await lckManager.reportNewIncomingConversation(uuid: uuid, update: update)
                semaphore.signal()
            } catch {
                semaphore.signal()
            }
        }
        semaphore.wait()
    }
    
    @objc
    func endLiveCommunication() {
        dictionaryPayload = nil
        if let conversation = lckManager.conversations.first {
            print("=======*******======endLiveCommunication")
            lckManager.reportConversationEvent(.conversationEnded(Date(), .remoteEnded), for: conversation)
        }
    }
    
    
    @objc
    func handleRouteChange(notification: Notification) {
        let session = AVAudioSession.sharedInstance()
        for output in session.currentRoute.outputs {
            if output.portType == .builtInSpeaker {
                XMPushLiveCommunicationBridge.updateSpeaker(on: true)
            } else {
                XMPushLiveCommunicationBridge.updateSpeaker(on: false)
            }
        }
    }

}



@available(iOS 17.4, *)
extension XMPushLiveCommunicationManager: ConversationManagerDelegate {
    func conversationManager(_ manager: ConversationManager, conversationChanged conversation: Conversation) {
        print("=======*******======conversationManager:\(conversation.state)")

    }
    
    func conversationManagerDidBegin(_ manager: ConversationManager) {
        print("=======*******======conversationManagerDidBegin")

    }
    
    func conversationManagerDidReset(_ manager: ConversationManager) {
        print("=======*******======conversationManagerDidReset")

    }
    
    func conversationManager(_ manager: ConversationManager, perform action: ConversationAction) {
        print("=======*******======\(action)")

        if action is JoinConversationAction {
            if ((self.dictionaryPayload?.count ?? 0) >= 0) {
                XMPushLiveCommunicationBridge.autoAnswerReceiveRtcEngineMessage(self.dictionaryPayload)
                action.fulfill()
            } else {
                action.fail()
            }
        } else if action is EndConversationAction {
            if ((self.dictionaryPayload?.count ?? 0) >= 0) {
                if (action.state == .idle) {
                    XMPushLiveCommunicationBridge.autoHangupReceiveRtcEngineMessage(self.dictionaryPayload)
                }
                action.fulfill()
            } else {
                action.fail()
            }
        } else if action is MuteConversationAction {
            let mutableAction = action as! MuteConversationAction
            if (action.state == .idle) {
                XMPushLiveCommunicationBridge.updateMute(on: mutableAction.isMuted)
            }
            action.fulfill()
        }
    }
    
    func conversationManager(_ manager: ConversationManager, timedOutPerforming action: ConversationAction) {
        print("=======*******======timedOutPerforming")

    }
    
    func conversationManager(_ manager: ConversationManager, didActivate audioSession: AVAudioSession) {
        print("=======*******======audioSession")

    }
    
    func conversationManager(_ manager: ConversationManager, didDeactivate audioSession: AVAudioSession) {
        print("=======*******======didDeactivate")

    }

}





//MARK: --------- PKPushRegistryDelegate
@available(iOS 17.4, *)
extension XMPushLiveCommunicationManager: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        DispatchQueue.main.async {
            if let closure = self.didUpdateDeviceTokenClosure {
                closure(token)
            }
        }
        print("PushKit Token: \(token)")
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
            
        reportNewIncomingConversation(payload: payload.dictionaryPayload)
        completion()
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("PushKit Token Invalidated")
    }
}
