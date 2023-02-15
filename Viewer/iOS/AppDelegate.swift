//
//  AppDelegate.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 16/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        .init(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}
