//
//  EditingImageCells.swift
//  ZLImageEditor
//
//  Created by iMac on 06/10/25.
//

import UIKit

protocol ZLEditingImageStickerDelegate {
    func stickerBeginOperation(_ sticker: ZLBaseStickerView)
    func stickerEndOperation(_ sticker: ZLBaseStickerView, point: CGPoint)
    func showInputTextVC(_ textSticker: ZLTextStickerView, editText text: String)
    func stickerDidDelete(_ sticker: ZLBaseStickerView)
}

class ZLEditingImageCells: UICollectionViewCell {
    
    var delegate: ZLEditingImageStickerDelegate?
    var stickerInitialPosition = CGPoint(x: 0, y: 0)
    
    open lazy var containerView: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        return view
    }()
    
    lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }()
    
    lazy var stickersContainer = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(containerView)
        containerView.addSubview(imageView)
        containerView.addSubview(stickersContainer)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setImageView(image: ZLEditedImages) {
        var shouldSwapSize = false
        var imageRect = CGSize(width: image.filteredImage.size.width, height: image.filteredImage.size.height)
        
        let transform = CGAffineTransform(rotationAngle: 0)
        imageView.transform = transform
        
        stickersContainer.subviews.forEach { view in
            view.removeFromSuperview()
        }
        
        if let editRect = image.editing?.clipStatus {
            imageRect = editRect.editRect.size
            shouldSwapSize = editRect.angle.zl.toPi.truncatingRemainder(dividingBy: .pi) != 0
            let transform = CGAffineTransform(rotationAngle: editRect.angle.zl.toPi)
            imageView.transform = transform
        }
        
        imageView.image = image.filteredImage
        
        let rectWidth = contentView.bounds.width - (60 * screenHeightRatio)
        let rectheight = contentView.bounds.height
        let ratio = min(rectWidth / imageRect.width, rectheight / imageRect.height)
        let w = (ratio * imageRect.width)
        let h = (ratio * imageRect.height)
        
        let imageWidth = shouldSwapSize ? (image.image.size.height * ratio) : (image.image.size.width * ratio)
        let imageHeight = shouldSwapSize ? (image.image.size.width * ratio) : (image.image.size.height * ratio)

        let rect = image.editing?.clipStatus?.editRect
        let x = (contentView.bounds.width - w) / 2
        let y = (contentView.bounds.height - h) / 2
        
        containerView.frame = CGRect(x: x,
                                     y: y,
                                     width: w,
                                     height: h)
        imageView.frame = CGRect(x: -(rect?.origin.x ?? 0) * ratio,
                                 y: -(rect?.origin.y ?? 0) * ratio,
                                 width: imageWidth,
                                 height: imageHeight)
        stickersContainer.frame = containerView.bounds
        
        if let stickers = image.editing?.stickers, !stickers.isEmpty {
            let stickerList = stickers.compactMap {
                ZLBaseStickerView.initWithState($0)
            }
            
            for stickerView in stickerList {
                stickersContainer.addSubview(stickerView)
                stickerView.frame = stickerView.originFrame
                stickerView.delegate = self
            }
        }
    }
}

//MARK: ZLStickerViewDelegate
extension ZLEditingImageCells: ZLStickerViewDelegate {
    func stickerDidDelete(_ sticker: ZLBaseStickerView) {
        delegate?.stickerDidDelete(sticker)
    }
    
    func stickerBeginOperation(_ sticker: ZLBaseStickerView, panGes: UIPanGestureRecognizer) {
        stickerInitialPosition = panGes.location(in: stickersContainer)//sticker.originFrame.origin
        delegate?.stickerBeginOperation(sticker)
        stickersContainer.bringSubviewToFront(sticker)
        stickersContainer.subviews.forEach { view in
            if view !== sticker {
                (view as? ZLStickerViewAdditional)?.resetState()
                (view as? ZLStickerViewAdditional)?.gesIsEnabled = false
            }
        }
    }
    
    func stickerOnOperation(_ sticker: ZLBaseStickerView, panGes: UIPanGestureRecognizer) {
    }
    
    func stickerEndOperation(_ sticker: ZLBaseStickerView, panGes: UIPanGestureRecognizer) {
        var point = panGes.location(in: stickersContainer)
        let stickerOrigin = sticker.originFrame.origin
        
        let xDiff = point.x - stickerInitialPosition.x
        let yDiff = point.y - stickerInitialPosition.y
        point = CGPoint(x: stickerOrigin.x + xDiff,
                        y: stickerOrigin.y + yDiff)
        delegate?.stickerEndOperation(sticker, point: point)
        
        stickersContainer.subviews.forEach { view in
            (view as? ZLStickerViewAdditional)?.gesIsEnabled = true
        }
    }
    
    func stickerDidTap(_ sticker: ZLBaseStickerView) {
        stickersContainer.bringSubviewToFront(sticker)
        stickersContainer.subviews.forEach { view in
            if view !== sticker {
                (view as? ZLStickerViewAdditional)?.resetState()
            }
        }
    }
    
    func sticker(_ textSticker: ZLTextStickerView, editText text: String) {
        delegate?.showInputTextVC(textSticker, editText: text)
    }
}
