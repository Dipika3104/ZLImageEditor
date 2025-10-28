//
//  ImageEditor.swift
//  SwiftUIExample
//
//  Created by long on 2025/6/17.
//

import Foundation
import SwiftUI
import ZLImageEditor

struct ImageEditorWrapper: UIViewControllerRepresentable {
    @Binding var originalImage: [UIImage]
    @Binding var editImage: [UIImage]?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let vc = ZLEditImageViewController(images: originalImage)
        vc.editFinishBlock = { editImage in
            self.editImage = editImage
        }
        vc.cancelBlock = {
            debugPrint("Cancel Edit")
        }
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        
    }
}
