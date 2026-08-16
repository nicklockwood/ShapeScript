//
//  AppDelegate.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 16/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import UIKit

@main @MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var firstLaunchOfNewVersion: Bool = false

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        firstLaunchOfNewVersion = (Settings.shared.appVersion != appVersion)
        if firstLaunchOfNewVersion {
            Settings.shared.previousAppVersion = Settings.shared.appVersion
            Settings.shared.appVersion = appVersion
        }
        return true
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let activityType = options.userActivities.first?.activityType ??
            connectingSceneSession.stateRestorationActivity?.activityType

        if activityType == documentationActivityType ||
            connectingSceneSession.configuration.name == documentationSceneConfigurationName
        {
            let configuration = UISceneConfiguration(
                name: documentationSceneConfigurationName,
                sessionRole: connectingSceneSession.role
            )
            configuration.delegateClass = DocumentationSceneDelegate.self
            return configuration
        }

        let configuration = UISceneConfiguration(
            name: mainSceneConfigurationName,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(
        _: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        guard sceneSessions.contains(where: {
            $0.configuration.name == mainSceneConfigurationName
        }) else {
            return
        }
        UIApplication.shared.closeDocumentationScenesIfNoMainScenesRemain()
    }
}
