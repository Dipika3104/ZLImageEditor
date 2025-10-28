//
//  ZLMediaListCell.swift
//  ZLImageEditor
//
//  Created by iMac on 26/09/25.
//

import UIKit

class ZLMediaListCell: UICollectionViewCell {
    lazy var image = UIImageView(frame: contentView.bounds)
    lazy var overlayView = UIView(frame: contentView.bounds)
    lazy var editingIcon = UIImageView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        image.frame = contentView.bounds
        image.contentMode = .scaleAspectFill
        
        editingIcon.image = UIImage(named: "ic_editing")
        editingIcon.frame = contentView.bounds
        editingIcon.contentMode = .center
        
        overlayView.frame = contentView.bounds
        overlayView.backgroundColor = .black.withAlphaComponent(0.3)
        
        contentView.backgroundColor = .lightGray.withAlphaComponent(0.3)
        contentView.layer.cornerRadius = 3
        contentView.clipsToBounds = true
        contentView.addSubview(image)
        contentView.addSubview(overlayView)
        contentView.addSubview(editingIcon)
    }
    
    func setEditingView(isEditing:Bool) {
        overlayView.isHidden = !isEditing
        editingIcon.isHidden = !isEditing
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
