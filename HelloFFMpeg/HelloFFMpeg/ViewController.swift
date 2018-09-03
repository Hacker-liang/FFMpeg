//
//  ViewController.swift
//  HelloFFMpeg
//
//  Created by 梁鹏帅 on 2018/8/28.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    var audioPlayer: PSAudioPlayer?

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction func startPlayAction(_ sender: Any) {
        if self.audioPlayer == nil {
            audioPlayer = PSAudioPlayer(filePath: CommonUtil.bundlePath("111.aac"))
        }

        self.audioPlayer?.start();
    }
    
    @IBAction func stopPlayAction(_ sender: Any) {
        self.audioPlayer?.stop();
    }
    
}

