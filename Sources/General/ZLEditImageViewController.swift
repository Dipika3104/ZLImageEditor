//
//  ZLEditImageViewController.swift
//  ZLImageEditor
//
//  Created by long on 2020/8/26.
//
//  Copyright (c) 2020 Long Zhang <495181165@qq.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import UIKit
import SwiftUI

public struct ZLClipStatus {
    var editRect: CGRect
    var angle: CGFloat = 0
    var ratio: ZLImageClipRatio?
    
    public init(
        editRect: CGRect,
        angle: CGFloat = 0,
        ratio: ZLImageClipRatio? = nil
    ) {
        self.editRect = editRect
        self.angle = angle
        self.ratio = ratio
    }
}

public struct ZLAdjustStatus {
    var brightness: Float = 0
    var contrast: Float = 0
    var saturation: Float = 0

    var allValueIsZero: Bool {
        brightness == 0 && contrast == 0 && saturation == 0
    }
    
    public init(
        brightness: Float = 0,
        contrast: Float = 0,
        saturation: Float = 0
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
    }
}

struct ZLEditedImages {
    var image: UIImage
    var filteredImage: UIImage
    var editing: ZLEditImageModel? = nil
    var actions: [ZLEditorAction] = []
    var redoActions: [ZLEditorAction] = []
}

public class ZLEditImageModel: NSObject {
    public let drawPaths: [ZLDrawPath]
    
    public let mosaicPaths: [ZLMosaicPath]
    
    public var clipStatus: ZLClipStatus?
    
    public let adjustStatus: ZLAdjustStatus?
    
    public var selectFilter: ZLFilter?
    
    public var stickers: [ZLBaseStickertState]
    
    public let actions: [ZLEditorAction]
    
    public init(
        drawPaths: [ZLDrawPath] = [],
        mosaicPaths: [ZLMosaicPath] = [],
        clipStatus: ZLClipStatus? = nil,
        adjustStatus: ZLAdjustStatus? = nil,
        selectFilter: ZLFilter? = nil,
        stickers: [ZLBaseStickertState] = [],
        actions: [ZLEditorAction] = []
    ) {
        self.drawPaths = drawPaths
        self.mosaicPaths = mosaicPaths
        self.clipStatus = clipStatus
        self.adjustStatus = adjustStatus
        self.selectFilter = selectFilter
        self.stickers = stickers
        self.actions = actions
        super.init()
    }
}

public protocol EmojiPickerDelegate: AnyObject {
    /// Provides chosen emoji.
    ///
    /// - Parameter emoji: String emoji.
    func didGetEmoji(emoji: String)
}

open class ZLEditImageViewController: UIViewController {
    
    /// The view containing the anchor rectangle for the popover.
    public var sourceView: UIView? {
        didSet {
            popoverPresentationController?.sourceView = sourceView
        }
    }
    
    public var arrowDirection: PickerArrowDirectionMode = .up
    public var customHeight: CGFloat?
    public var horizontalInset: CGFloat = 0
    public var isDismissedAfterChoosing: Bool = true
    
    public var selectedEmojiCategoryTintColor: UIColor? = .systemBlue {
        didSet {
            guard let selectedEmojiCategoryTintColor = selectedEmojiCategoryTintColor else { return }
            emojiStickerPickerView.selectedEmojiCategoryTintColor = selectedEmojiCategoryTintColor
        }
    }
    
    public var feedbackGeneratorStyle: UIImpactFeedbackGenerator.FeedbackStyle? {
        didSet {
            guard let feedBackGeneratorStyle = feedbackGeneratorStyle else {
                feedbackGenerator = nil
                return
            }
            feedbackGenerator = UIImpactFeedbackGenerator(style: feedBackGeneratorStyle)
        }
    }
    
    lazy var emojiStickerPickerView: EmojiPickerView = {
        let view = EmojiPickerView()
        view.isHidden = true
        return view
    }()
    private var feedbackGenerator: UIImpactFeedbackGenerator?
    private var viewModel: EmojiPickerViewModelProtocol
    
    // MARK: - Private Methods
    private func bindViewModel() {
        viewModel.selectedEmoji.bind { [unowned self] emoji in
            feedbackGenerator?.impactOccurred()
            
            if isDismissedAfterChoosing {
                imageStickerBtnClick(show: false)
            }
        }
        
        viewModel.selectedEmojiCategoryIndex.bind { [unowned self] categoryIndex in
            self.emojiStickerPickerView.updateSelectedCategoryIcon(with: categoryIndex)
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupDelegates() {
        emojiStickerPickerView.delegate = self
        emojiStickerPickerView.backgroundColor = .white
        emojiStickerPickerView.collectionView.delegate = self
        emojiStickerPickerView.collectionView.dataSource = self
    }
    
    static let maxDrawLineImageWidth: CGFloat = 600
    
    static let shadowColorFrom = UIColor.black.withAlphaComponent(0.35).cgColor
    
    static let shadowColorTo = UIColor.clear.cgColor
    
    public var drawColViewH: CGFloat = 50
    
    public var filterColViewH: CGFloat = 100 * screenHeightRatio
    
    public var adjustColViewH: CGFloat = 60
    
    public var ashbinSize = CGSize(width: 160, height: 80)
    
    open lazy var containerView: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        return view
    }()
    
    // Show image.
    open lazy var imageView: UIImageView = {
        let view = UIImageView(image: originalImage)
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.backgroundColor = .clear
        return view
    }()
    
    open lazy var topShadowView: ZLPassThroughView = {
        let shadowView = ZLPassThroughView()
        shadowView.findResponderSticker = { [weak self] point in
            self?.findResponderSticker(point)
        }
        return shadowView
    }()
    
    open lazy var topShadowLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [ZLEditImageViewController.shadowColorFrom, ZLEditImageViewController.shadowColorTo]
        layer.locations = [0, 1]
        return layer
    }()
     
    open lazy var bottomShadowView: ZLPassThroughView = {
        let shadowView = ZLPassThroughView()
        shadowView.findResponderSticker = { [weak self] point in
            self?.findResponderSticker(point)
        }
        return shadowView
    }()
    
    open lazy var bottomShadowLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [ZLEditImageViewController.shadowColorTo, ZLEditImageViewController.shadowColorFrom]
        layer.locations = [0, 1]
        return layer
    }()
    
    open lazy var cancelBtn: ZLEnlargeButton = {
        let btn = ZLEnlargeButton(type: .custom)
        btn.setImage(UIImage(named: "ic_cancel"), for: .normal)
        btn.setImage(UIImage(named: "ic_cancel"), for: .selected)
        btn.backgroundColor = .clear
        btn.addTarget(self, action: #selector(cancelBtnClick), for: .touchUpInside)
        btn.enlargeInset = 30
        return btn
    }()
    
    open lazy var closeBtn: ZLEnlargeButton = {
        let btn = ZLEnlargeButton(type: .custom)
        btn.setImage(UIImage(named: "ic_cancel"), for: .normal)
        btn.setImage(UIImage(named: "ic_cancel"), for: .selected)
        btn.backgroundColor = .white
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOffset = CGSize(width: 2, height: 2)
        btn.layer.shadowOpacity = 0.3
        btn.layer.shadowRadius = 3
        btn.layer.cornerRadius = 15
        btn.isHidden = true
        btn.addTarget(self, action: #selector(closeFilterView), for: .touchUpInside)
        btn.enlargeInset = 30
        return btn
    }()
    
    open lazy var doneBtn: UIButton = {
        let btn = UIButton(type: .custom)
        btn.titleLabel?.font = ZLImageEditorLayout.bottomToolTitleFont
        btn.backgroundColor = .zl.editDoneBtnBgColor
        btn.setTitle(localLanguageTextValue(.editFinish), for: .normal)
        btn.setTitleColor(.zl.editDoneBtnTitleColor, for: .normal)
        btn.addTarget(self, action: #selector(doneBtnClick), for: .touchUpInside)
        btn.layer.masksToBounds = true
        btn.layer.cornerRadius = ZLImageEditorLayout.bottomToolBtnCornerRadius
        return btn
    }()
    
    open lazy var undoBtn: ZLEnlargeButton = {
        let btn = ZLEnlargeButton(type: .custom)
        btn.setImage(.zl.getImage("zl_undo"), for: .normal)
        btn.setImage(.zl.getImage("zl_undo"), for: .disabled)
        btn.isEnabled = !editorManager.actions.isEmpty
        btn.enlargeInset = 8
        btn.addTarget(self, action: #selector(undoBtnClick), for: .touchUpInside)
        return btn
    }()
    
    open lazy var redoBtn: ZLEnlargeButton = {
        let btn = ZLEnlargeButton(type: .custom)
        btn.setImage(.zl.getImage("zl_redo"), for: .normal)
        btn.setImage(.zl.getImage("zl_redo"), for: .disabled)
        btn.isEnabled = editorManager.actions.count != editorManager.redoActions.count
        btn.enlargeInset = 8
        btn.addTarget(self, action: #selector(redoBtnClick), for: .touchUpInside)
        return btn
    }()
    
    open lazy var editingImageCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: currentScreenSize.width, height: currentScreenSize.height * 0.45)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = .horizontal
        
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.delegate = self
        view.dataSource = self
        view.showsHorizontalScrollIndicator = false
        view.isPagingEnabled = true
        ZLEditingImageCells.zl.register(view)
        
        return view
    }()
    
    open lazy var editToolCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 35, height: 36)
        layout.minimumLineSpacing = 20
        layout.minimumInteritemSpacing = 20
        layout.scrollDirection = .horizontal
        
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.delegate = self
        view.dataSource = self
        view.showsHorizontalScrollIndicator = false
        ZLEditToolCell.zl.register(view)
        
        return view
    }()
    
    open lazy var mediaListCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 58 * screenHeightRatio, height: 58 * screenHeightRatio)
        layout.minimumLineSpacing = 5
        layout.minimumInteritemSpacing = 20
        layout.scrollDirection = .horizontal
        
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.delegate = self
        view.dataSource = self
        view.showsHorizontalScrollIndicator = false
        ZLMediaListCell.zl.register(view)
        
        return view
    }()
    
    open var drawColorCollectionView: UICollectionView?
    
    open var filterCollectionView: UICollectionView?
    
    open var adjustCollectionView: UICollectionView?
    
    open lazy var eraserBtn: ZLEnlargeButton = {
        let btn = ZLEnlargeButton(type: .custom)
        btn.setImage(.zl.getImage("zl_eraser"), for: .normal)
        btn.addTarget(self, action: #selector(eraserBtnClick), for: .touchUpInside)
        btn.isHidden = true
        btn.layer.cornerRadius = 18
        btn.layer.masksToBounds = true
        return btn
    }()
    
    open lazy var eraserBtnBgBlurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        view.isHidden = true
        view.layer.cornerRadius = 18
        view.layer.masksToBounds = true
        return view
    }()
    
    open lazy var eraserLineView: UIView = {
        let view = UIView()
        view.backgroundColor = .zl.rgba(89, 95, 107, 0.8)
        view.isHidden = true
        return view
    }()
    
    open lazy var eraserCircleView: UIImageView = {
        let imageView = UIImageView(image: .zl.getImage("zl_eraser_circle"))
        imageView.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        imageView.isHidden = true
        return imageView
    }()

    open lazy var ashbinView: UIView = {
        let view = UIView()
        view.backgroundColor = .zl.ashbinNormalBgColor
        view.layer.cornerRadius = 15
        view.layer.masksToBounds = true
        view.isHidden = true
        return view
    }()
    
    open lazy var ashbinImgView = UIImageView(image: .zl.getImage("zl_ashbin"), highlightedImage: .zl.getImage("zl_ashbin_open"))
    
    var tapGes = UITapGestureRecognizer()
    
    var adjustSlider: ZLAdjustSlider?
    
    var animateDismiss = true
    var isDraggingSticker = false
    
    var originalImage: UIImage
    var mediaList: [ZLEditedImages] = []
    
    // The frame after first layout, used in dismiss animation.
    var originalFrame: CGRect = .zero
    
    let tools: [ZLImageEditorConfiguration.EditTool]
    
    let adjustTools: [ZLImageEditorConfiguration.AdjustTool]
    
    var editImage: UIImage
    
    var editImageWithoutAdjust: UIImage
    
    var editImageAdjustRef: UIImage?
    
    var selectedIndex = 0
    
    // Show draw lines.
    lazy var drawingImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        return view
    }()
    
    // Show text and image stickers.
    lazy var stickersContainer = UIView()
    
    var mosaicImage: UIImage?
    
    // Show mosaic image
    var mosaicImageLayer: CALayer?
    
    // The mask layer of mosaicImageLayer
    var mosaicImageLayerMaskLayer: CAShapeLayer?
    
    var selectedTool: ZLImageEditorConfiguration.EditTool?
    
    var selectedAdjustTool: ZLImageEditorConfiguration.AdjustTool?
    
    let drawColors: [UIColor]
    
    var currentDrawColor = ZLImageEditorConfiguration.default().defaultDrawColor
    
    var drawPaths: [ZLDrawPath]
    
    var drawLineWidth: CGFloat = 6
    
    var mosaicPaths: [ZLMosaicPath]
    
    var mosaicLineWidth: CGFloat = 25
    
    var thumbnailFilterImages: [UIImage] = []
    
    // Cache the filter image of original image
    var filterImages: [String: UIImage] = [:]
    
    var currentFilter: ZLFilter
    
    var stickers: [ZLBaseStickerView] = []
    
    var isScrolling = false
    
    var shouldLayout = true
    
    var isApplyFilter = false
    
    var imageStickerContainerIsHidden = true

    var fontChooserContainerIsHidden = true
    
    private var currentClipStatus: ZLClipStatus

    private var preClipStatus: ZLClipStatus

    private var preStickerState: ZLBaseStickertState?

    private var currentAdjustStatus: ZLAdjustStatus

    private var preAdjustStatus: ZLAdjustStatus

    private var editorManager: ZLEditorManager
    
    private lazy var deleteDrawPaths: [ZLDrawPath] = []
    
    private var defaultDrawPathWidth: CGFloat = 0
    
    private var impactFeedback: UIImpactFeedbackGenerator?
    
    /// 是否允许交换图片宽高
    private var shouldSwapSize: Bool {
        currentClipStatus.angle.zl.toPi.truncatingRemainder(dividingBy: .pi) != 0
    }
    
    var imageSize: CGSize {
        if shouldSwapSize {
            return CGSize(width: originalImage.size.height, height: originalImage.size.width)
        } else {
            return originalImage.size
        }
    }
    
    var toolViewStateTimer: Timer?
    
    var hasAdjustedImage = false
    
    @objc public var editFinishBlock: (([UIImage]/*, ZLEditImageModel?*/) -> Void)?
    
    @objc public var cancelBlock: (() -> Void)?
    
    override open var prefersStatusBarHidden: Bool { true }
    
    override open var prefersHomeIndicatorAutoHidden: Bool { true }
    
    /// 延缓屏幕上下方通知栏弹出，避免手势冲突
    override open var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }
    
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        deviceIsiPhone() ? .portrait : .all
    }
    
    deinit {
        cleanToolViewStateTimer()
        zl_debugPrint("ZLEditImageViewController deinit")
    }
    
    @objc public class func showEditImageVC(
        parentVC: UIViewController?,
        animate: Bool = true,
        images: [UIImage],
        editModel: ZLEditImageModel? = nil,
        completion: (([UIImage]/*, ZLEditImageModel?*/) -> Void)?,
        cancelBlock: (() -> Void)? = nil
    ) {
        let vc = ZLEditImageViewController(images: images, editModel: editModel)
        vc.editFinishBlock = { ei/*, editImageModel*/ in
            completion?(ei)
        }
        vc.cancelBlock = {
            cancelBlock?()
        }
        vc.animateDismiss = animate
        vc.modalPresentationStyle = .fullScreen
        parentVC?.present(vc, animated: animate, completion: nil)
    }
    
    @objc public init(images: [UIImage], editModel: ZLEditImageModel? = nil) {
        
        for image in images {
            mediaList.append(ZLEditedImages(image: image,
                                            filteredImage: image,
                                            editing: ZLEditImageModel()))
        }
        
        var image = mediaList[selectedIndex].image
        if image.scale != 1,
           let cgImage = image.cgImage {
            image = image.zl.resize_vI(
                CGSize(width: cgImage.width, height: cgImage.height),
                scale: 1
            ) ?? image
        }
        
        originalImage = image.zl.fixOrientation()
        editImage = mediaList[selectedIndex].filteredImage
        editImageWithoutAdjust = originalImage
        currentClipStatus = mediaList[selectedIndex].editing?.clipStatus ?? ZLClipStatus(editRect: CGRect(origin: .zero, size: image.size))
        preClipStatus = currentClipStatus
        drawColors = ZLImageEditorConfiguration.default().drawColors
        currentFilter = .normal
        drawPaths = editModel?.drawPaths ?? []
        mosaicPaths = editModel?.mosaicPaths ?? []
        currentAdjustStatus = editModel?.adjustStatus ?? ZLAdjustStatus()
        preAdjustStatus = currentAdjustStatus
        
        let ts = ZLImageEditorConfiguration.default().tools
        tools = ts
        adjustTools = ZLImageEditorConfiguration.default().adjustTools
        selectedAdjustTool = adjustTools.first
        editorManager = ZLEditorManager(actions: editModel?.actions ?? [])
        
        let emojiManager = EmojiManager()
        viewModel = EmojiPickerViewModel(emojiManager: emojiManager)
        
        super.init(nibName: nil, bundle: nil)
        self.mediaListCollectionView.reloadData()
        
        editorManager.delegate = self
        
        if !drawColors.contains(currentDrawColor) {
            currentDrawColor = drawColors.first!
        }
        
        stickers = editModel?.stickers.compactMap {
            ZLBaseStickerView.initWithState($0)
        } ?? []
        
        //Emoji Picker Setup
        setupDelegates()
        bindViewModel()
    }
    
    func selectImage() {
        var image = mediaList[selectedIndex].image
        if image.scale != 1,
           let cgImage = image.cgImage {
            image = image.zl.resize_vI(
                CGSize(width: cgImage.width, height: cgImage.height),
                scale: 1
            ) ?? image
        }
        
        originalImage = image.zl.fixOrientation()
        editImage = originalImage
        currentClipStatus = mediaList[selectedIndex].editing?.clipStatus ?? ZLClipStatus(editRect: CGRect(origin: .zero, size: image.size))
        currentFilter = mediaList[selectedIndex].editing?.selectFilter ?? .normal
        isApplyFilter = false
        setViewOnFilter()
        setFilterViews(hidden: true)
        rotationImageView()
        resetContainerViewFrame()
        generateFilterImages()
        preClipStatus = currentClipStatus
        
        editorManager.actions = mediaList[selectedIndex].actions
        editorManager.redoActions = mediaList[selectedIndex].redoActions
        undoBtn.isEnabled = !editorManager.actions.isEmpty
        redoBtn.isEnabled = editorManager.actions.count != editorManager.redoActions.count
        
        editingImageCollectionView.scrollToItem(at: IndexPath(row: selectedIndex, section: 0), at: .centeredHorizontally, animated: true)
        editingImageCollectionView.reloadData()
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        
        rotationImageView()
        if tools.contains(.filter) {
            generateFilterImages()
        }
    }
    
    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        guard tools.contains(.draw) else { return }
        
        let width = drawLineWidth
        defaultDrawPathWidth = width
    }
    
    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard shouldLayout else {
            return
        }
        
        shouldLayout = false
        zl_debugPrint("edit image layout subviews")
        var insets = UIEdgeInsets.zero
        if #available(iOS 11.0, *) {
            insets = view.safeAreaInsets
        }
        insets.top = max(insets.top, 20)
        
        let w = currentScreenSize.width
        let h = currentScreenSize.height * 0.45
        let x = (currentScreenSize.width - w) / 2
        let y = (currentScreenSize.height - h) / 2
        
        editingImageCollectionView.frame = CGRect(x: x, y: y, width: w, height: h)
        
        resetContainerViewFrame()
        
        topShadowView.frame = CGRect(x: 0, y: 0, width: view.zl.width, height: 100 * screenHeightRatio)
        
        let bottomViewHeight = screenHeightRatio * 180
        bottomShadowView.frame = CGRect(x: 0, y: view.zl.height - bottomViewHeight - insets.bottom, width: view.zl.width, height: bottomViewHeight + insets.bottom)
        
        cancelBtn.frame = CGRect(x: 20, y: insets.top, width: 28, height: 28)
        redoBtn.frame = CGRect(x: view.zl.width - 15 - 30, y: insets.top, width: 30, height: 30)
        undoBtn.frame = CGRect(x: redoBtn.zl.left - 15 - 30, y: insets.top, width: 30, height: 30)
        
        let screenHalfWidth = (view.zl.width - (60*screenHeightRatio))/2
        let mediaListCvWidth: CGFloat = min(((70.0*screenHeightRatio) * CGFloat(mediaList.count)), view.zl.width - 60.0)
        let mediaListCvX: CGFloat = (screenHalfWidth - (mediaListCvWidth/2.0)) + (30*screenHeightRatio)
        mediaListCollectionView.frame = CGRect(x: mediaListCvX, y: (100*screenHeightRatio), width: mediaListCvWidth, height: (66*screenHeightRatio))
        
        eraserBtn.frame = CGRect(x: 20, y: 30 + (drawColViewH - 36) / 2, width: 36, height: 36)
        eraserBtnBgBlurView.frame = eraserBtn.frame
        eraserLineView.frame = CGRect(x: eraserBtn.zl.right + 11, y: eraserBtn.frame.midY - 10, width: 1, height: 20)
        drawColorCollectionView?.frame = CGRect(x: eraserLineView.zl.right + 11, y: 46, width: view.zl.width - eraserLineView.zl.right - 31, height: drawColViewH)
        
        adjustCollectionView?.frame = CGRect(x: 20, y: 46, width: view.zl.width - 40, height: adjustColViewH)
        if ZLImageEditorUIConfiguration.default().adjustSliderType == .vertical {
            adjustSlider?.frame = CGRect(x: view.zl.width - 60, y: view.zl.height / 2 - 100, width: 60, height: 200)
        } else {
            let sliderHeight: CGFloat = 60
            let sliderWidth = UIDevice.current.userInterfaceIdiom == .phone ? view.zl.width - 100 : view.zl.width / 2
            adjustSlider?.frame = CGRect(
                x: (view.zl.width - sliderWidth) / 2,
                y: bottomShadowView.zl.top - sliderHeight,
                width: sliderWidth,
                height: sliderHeight
            )
        }
        
        filterCollectionView?.frame = CGRect(x: 20, y: 46, width: view.zl.width - 40, height: filterColViewH)
        closeBtn.frame = CGRect(x: (view.bounds.width - 30)/2 , y: 6, width: 30, height: 30)
        
        ashbinView.frame = CGRect(
            x: (view.zl.width - ashbinSize.width) / 2,
            y: view.zl.height - ashbinSize.height - 40,
            width: ashbinSize.width,
            height: ashbinSize.height
        )
        ashbinImgView.frame = CGRect(
            x: (ashbinSize.width - 25) / 2,
            y: 15,
            width: 25,
            height: 25
        )
        
        let toolY: CGFloat = 118 * screenHeightRatio
        
        let doneBtnH = ZLImageEditorLayout.bottomToolBtnH
        let doneBtnW: CGFloat = 160 * screenHeightRatio
        doneBtn.frame = CGRect(x: (view.zl.width/2) - (doneBtnW/2), y: toolY, width: doneBtnW, height: doneBtnH)
        
        let editCvWidth: CGFloat = CGFloat(((tools.count * (35 + 20)) - 20))
        editToolCollectionView.frame = CGRect(x: (view.bounds.width/2) - (editCvWidth/2),
                                              y: 0,
                                              width: editCvWidth,
                                              height: 38)
        
        let emojiCvY = (currentScreenSize.height * 0.5)
        emojiStickerPickerView.frame = CGRect(x: 0, y: emojiCvY, width: currentScreenSize.width, height: currentScreenSize.height * 0.5)
        
        if !drawPaths.isEmpty {
            drawLine()
        }
        if !mosaicPaths.isEmpty {
            generateNewMosaicImage()
        }
        
        if let index = drawColors.firstIndex(where: { $0 == self.currentDrawColor }) {
            drawColorCollectionView?.scrollToItem(at: IndexPath(row: index, section: 0), at: .centeredHorizontally, animated: false)
        }
    }

    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        shouldLayout = true
    }
    
    func generateFilterImages() {
        let size: CGSize
        let ratio = (originalImage.size.width / originalImage.size.height)
        let fixLength: CGFloat = 200
        if ratio >= 1 {
            size = CGSize(width: fixLength * ratio, height: fixLength)
        } else {
            size = CGSize(width: fixLength, height: fixLength / ratio)
        }
        let thumbnailImage = originalImage.zl.resize(size) ?? originalImage
        
        DispatchQueue.global().async {
            self.thumbnailFilterImages = ZLImageEditorConfiguration.default().filters.map { $0.applier?(thumbnailImage) ?? thumbnailImage }
            
            DispatchQueue.main.async {
                self.filterCollectionView?.reloadData()
                self.filterCollectionView?.performBatchUpdates {} completion: { _ in
                    if let index = ZLImageEditorConfiguration.default().filters.firstIndex(where: { $0 == self.currentFilter }) {
                        self.filterCollectionView?.scrollToItem(at: IndexPath(row: index, section: 0), at: .centeredHorizontally, animated: false)
                    }
                }
            }
        }
    }
    
    func resetContainerViewFrame() {
        imageView.image = editImage
        let editRect = currentClipStatus.editRect
        
        let editSize = editRect.size
        let screenSize = view.bounds.size
        let rectWidth = screenSize.width - (60 * screenHeightRatio)
        let rectheight = screenSize.height * 0.45
        let ratio = min(rectWidth / editSize.width, rectheight / editSize.height)
        let w = ratio * editSize.width
        let h = ratio * editSize.height
        let x = (screenSize.width - w) / 2
        let y = (screenSize.height - h) / 2
        containerView.frame = CGRect(x: x, y: y, width: w, height: h)
        
        if currentClipStatus.ratio?.isCircle == true {
            let mask = CAShapeLayer()
            let path = UIBezierPath(arcCenter: CGPoint(x: w / 2, y: h / 2), radius: w / 2, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            mask.path = path.cgPath
            containerView.layer.mask = mask
        } else {
            containerView.layer.mask = nil
        }
        
        let scaleImageOrigin = CGPoint(x: -editRect.origin.x * ratio, y: -editRect.origin.y * ratio)
        let scaleImageSize = CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
        imageView.frame = CGRect(origin: scaleImageOrigin, size: scaleImageSize)
        mosaicImageLayer?.frame = imageView.bounds
        mosaicImageLayerMaskLayer?.frame = imageView.bounds
        drawingImageView.frame = imageView.frame
        stickersContainer.frame = imageView.frame
        isScrolling = false
    }
    
    func setupUI() {
        view.backgroundColor = .white
        imageView.backgroundColor = .red
        
        view.addSubview(editingImageCollectionView)
        containerView.backgroundColor = .green
        containerView.addSubview(drawingImageView)
        containerView.addSubview(stickersContainer)
        
        view.addSubview(topShadowView)
        topShadowView.addSubview(cancelBtn)
        topShadowView.addSubview(undoBtn)
        topShadowView.addSubview(redoBtn)
        
        view.addSubview(bottomShadowView)
        view.addSubview(mediaListCollectionView)
        bottomShadowView.addSubview(editToolCollectionView)
        bottomShadowView.addSubview(doneBtn)
        bottomShadowView.addSubview(closeBtn)
        
        view.addSubview(emojiStickerPickerView)
        view.bringSubviewToFront(emojiStickerPickerView)
        
        if tools.contains(.draw) {
            bottomShadowView.addSubview(eraserBtnBgBlurView)
            bottomShadowView.addSubview(eraserBtn)
            bottomShadowView.addSubview(eraserLineView)
            containerView.addSubview(eraserCircleView)
            
            impactFeedback = UIImpactFeedbackGenerator(style: .light)

            let drawColorLayout = UICollectionViewFlowLayout()
            let drawColorItemWidth: CGFloat = 36
            drawColorLayout.itemSize = CGSize(width: drawColorItemWidth, height: drawColorItemWidth)
            drawColorLayout.minimumLineSpacing = 0
            drawColorLayout.minimumInteritemSpacing = 0
            drawColorLayout.scrollDirection = .horizontal
            let drawColorTopBottomInset = (drawColViewH - drawColorItemWidth) / 2
            drawColorLayout.sectionInset = UIEdgeInsets(top: drawColorTopBottomInset, left: 0, bottom: drawColorTopBottomInset, right: 0)
            
            let drawCV = UICollectionView(frame: .zero, collectionViewLayout: drawColorLayout)
            drawCV.backgroundColor = .clear
            drawCV.delegate = self
            drawCV.dataSource = self
            drawCV.isHidden = true
            bottomShadowView.addSubview(drawCV)
            
            ZLDrawColorCell.zl.register(drawCV)
            drawColorCollectionView = drawCV
        }
        
        if tools.contains(.filter) {
            if let applier = currentFilter.applier {
                let image = applier(originalImage)
                editImage = image
                editImageWithoutAdjust = image
                filterImages[currentFilter.name] = image
            }
            
            let filterLayout = UICollectionViewFlowLayout()
            filterLayout.itemSize = CGSize(width: filterColViewH - 30, height: filterColViewH - 10)
            filterLayout.minimumLineSpacing = 15
            filterLayout.minimumInteritemSpacing = 15
            filterLayout.scrollDirection = .horizontal
            filterLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
            
            let filterCV = UICollectionView(frame: .zero, collectionViewLayout: filterLayout)
            filterCV.backgroundColor = .clear
            filterCV.delegate = self
            filterCV.dataSource = self
            filterCV.isHidden = true
            bottomShadowView.addSubview(filterCV)
            
            ZLFilterImageCell.zl.register(filterCV)
            filterCollectionView = filterCV
        }
        
        if tools.contains(.adjust) {
            editImage = editImage.zl.adjust(
                brightness: currentAdjustStatus.brightness,
                contrast: currentAdjustStatus.contrast,
                saturation: currentAdjustStatus.saturation
            ) ?? editImage
            
            let adjustLayout = UICollectionViewFlowLayout()
            adjustLayout.itemSize = CGSize(width: adjustColViewH, height: adjustColViewH)
            adjustLayout.minimumLineSpacing = 10
            adjustLayout.minimumInteritemSpacing = 10
            adjustLayout.scrollDirection = .horizontal
            
            let adjustCV = UICollectionView(frame: .zero, collectionViewLayout: adjustLayout)
            
            adjustCV.backgroundColor = .clear
            adjustCV.delegate = self
            adjustCV.dataSource = self
            adjustCV.isHidden = true
            adjustCV.showsHorizontalScrollIndicator = false
            bottomShadowView.addSubview(adjustCV)
            
            ZLAdjustToolCell.zl.register(adjustCV)
            adjustCollectionView = adjustCV
            
            adjustSlider = ZLAdjustSlider()
            if let selectedAdjustTool = selectedAdjustTool {
                changeAdjustTool(selectedAdjustTool)
            }
            adjustSlider?.beginAdjust = { [weak self] in
                guard let `self` = self else { return }
                self.preAdjustStatus = self.currentAdjustStatus
            }
            adjustSlider?.valueChanged = { [weak self] value in
                self?.adjustValueChanged(value)
            }
            adjustSlider?.endAdjust = { [weak self] in
                guard let `self` = self else { return }
                self.editorManager.storeAction(
                    .adjust(oldStatus: self.preAdjustStatus, newStatus: self.currentAdjustStatus)
                )
                self.hasAdjustedImage = true
            }
            adjustSlider?.isHidden = true
            view.addSubview(adjustSlider!)
        }
        
        view.addSubview(ashbinView)
        ashbinView.addSubview(ashbinImgView)
        
        let asbinTipLabel = UILabel(frame: CGRect(x: 0, y: ashbinSize.height - 34, width: ashbinSize.width, height: 34))
        asbinTipLabel.font = UIFont.systemFont(ofSize: 12)
        asbinTipLabel.textAlignment = .center
        asbinTipLabel.textColor = .white
        asbinTipLabel.text = localLanguageTextValue(.textStickerRemoveTips)
        asbinTipLabel.numberOfLines = 2
        asbinTipLabel.lineBreakMode = .byCharWrapping
        ashbinView.addSubview(asbinTipLabel)
        
        if tools.contains(.mosaic) {
            mosaicImage = editImage.zl.mosaicImage()
            
            mosaicImageLayer = CALayer()
            mosaicImageLayer?.contents = mosaicImage?.cgImage
            imageView.layer.addSublayer(mosaicImageLayer!)
            
            mosaicImageLayerMaskLayer = CAShapeLayer()
            mosaicImageLayerMaskLayer?.strokeColor = UIColor.blue.cgColor
            mosaicImageLayerMaskLayer?.fillColor = nil
            mosaicImageLayerMaskLayer?.lineCap = .round
            mosaicImageLayerMaskLayer?.lineJoin = .round
            imageView.layer.addSublayer(mosaicImageLayerMaskLayer!)
            
            mosaicImageLayer?.mask = mosaicImageLayerMaskLayer
        }
        
        if tools.contains(.imageSticker) {
            
            ZLImageEditorConfiguration.default().imageStickerContainerView?.hideBlock = { [weak self] in
                self?.setToolView(show: true)
                self?.imageStickerContainerIsHidden = true
            }
            
            ZLImageEditorConfiguration.default().imageStickerContainerView?.selectImageBlock = { [weak self] image in
                self?.addImageStickerView(image)
            }
        }

        if tools.contains(.textSticker) {
            ZLImageEditorConfiguration.default().fontChooserContainerView?.hideBlock = { [weak self] in
                self?.setToolView(show: true)
                self?.fontChooserContainerIsHidden = true
            }

            ZLImageEditorConfiguration.default().fontChooserContainerView?.selectFontBlock = { [weak self] font in
                self?.showInputTextVC(font: font, completion: { [weak self] text, textColor, font, image, style in
                    self?.addTextStickersView(text, textColor: textColor, font: font, image: image, style: style)
                })
            }
        }
        
        tapGes = UITapGestureRecognizer(target: self, action: #selector(tapAction(_:)))
        tapGes.delegate = self
        tapGes.isEnabled = true
        view.addGestureRecognizer(tapGes)
        
        stickers.forEach { self.addSticker($0) }
        
        for gesture in view.gestureRecognizers ?? [] {
            gesture.delegate = self
        }
    }
    
    /// 根据point查找可响应的sticker
    func findResponderSticker(_ point: CGPoint) -> UIView? {
        // 倒序查找subview
        for sticker in stickersContainer.subviews.reversed() {
            let rect = stickersContainer.convert(sticker.frame, to: view)
            if rect.contains(point) {
                return sticker
            }
        }
        
        return nil
    }
    
    func rotationImageView() {
        let transform = CGAffineTransform(rotationAngle: currentClipStatus.angle.zl.toPi)
        imageView.transform = transform
    }
    
    @objc func cancelBtnClick() {
        self.cancelBlock?()
    }
    
    func drawBtnClick() {
        let isSelected = selectedTool != .draw
        if isSelected {
            selectedTool = .draw
        } else {
            selectedTool = nil
        }
        
        setDrawViews(hidden: !isSelected)
        setFilterViews(hidden: true)
        setAdjustViews(hidden: true)
    }
    
    @objc private func eraserBtnClick() {
        switchEraserBtnStatus(!eraserBtn.isSelected)
    }
    
    private func switchEraserBtnStatus(_ isSelected: Bool, reloadData: Bool = true) {
        guard eraserBtn.isSelected != isSelected else { return }
        
        eraserBtn.isSelected = isSelected
        eraserBtnBgBlurView.isHidden = !isSelected
        
        if reloadData {
            drawColorCollectionView?.reloadData()
        }
    }
    
    func clipBtnClick() {
        preClipStatus = currentClipStatus
        
        var currentEditImage = editImage
        autoreleasepool {
            currentEditImage = buildImage()
        }
        
        let vc = ZLClipImageViewController(image: currentEditImage, status: currentClipStatus)
        let rect = containerView.frame//mainScrollView.convert(containerView.frame, to: view)
        vc.presentingEditViewController = self
        vc.presentAnimateFrame = rect
        vc.presentAnimateImage = currentEditImage.zl
            .clipImage(
                angle: currentClipStatus.angle,
                editRect: currentClipStatus.editRect,
                isCircle: currentClipStatus.ratio?.isCircle ?? false
            )
        vc.modalPresentationStyle = .fullScreen
        
        vc.clipDoneBlock = { [weak self] angle, editRect, selectRatio in
            guard let `self` = self else { return }
            
            self.clipImage(status: ZLClipStatus(editRect: editRect, angle: angle, ratio: selectRatio))
        }
        
        present(vc, animated: false) {
            self.topShadowView.alpha = 0
            self.mediaListCollectionView.alpha = 0
            self.bottomShadowView.alpha = 0
            self.adjustSlider?.alpha = 0
        }
        
        selectedTool = nil
        setDrawViews(hidden: true)
        setFilterViews(hidden: true)
        setAdjustViews(hidden: true)
    }
    
    private func clipImage(status: ZLClipStatus) {
        let oldAngle = currentClipStatus.angle
        if oldAngle != status.angle {
            currentClipStatus.angle = status.angle
            mediaList[selectedIndex].editing?.clipStatus?.angle = status.angle
        }
        
        currentClipStatus.editRect = status.editRect
        currentClipStatus.ratio = status.ratio
        mediaList[selectedIndex].editing?.clipStatus = status
        editingImageCollectionView.reloadData()
        resetContainerViewFrame()
    }
    
    func imageStickerBtnClick(show:Bool) {
        tapGes.isEnabled = !show
        emojiStickerPickerView.isHidden = !show
        doneBtn.isHidden = show
        editToolCollectionView.isHidden = show
    }
    
    @objc func closeEmojiPicker() {
        imageStickerBtnClick(show:false)
    }
    
    func getEmojiSticker(text:String) {
        if text != "" {
            var image: UIImage?
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 50)
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let imageSize = CGSize(width: textSize.width,
                                   height: textSize.height)
            
            image = UIGraphicsImageRenderer.zl.renderImage(size: imageSize) { context in
                
                let textRect = CGRect(x: 0, y: 0, width: textSize.width, height: textSize.height)
                (text as NSString).draw(in: textRect,
                                        withAttributes: [
                                            .font: UIFont.systemFont(ofSize: 50)
                                        ])
            }
            
            if let image = image {
                addImageStickerView(image)
            }
        }
    }
    
    func textStickerBtnClick() {
            showInputTextVC(font: ZLImageEditorConfiguration.default().textStickerDefaultFont) { [weak self] text, textColor, font, image, style in
                self?.addTextStickersView(text, textColor: textColor, font: font, image: image, style: style)
            }
        
        selectedTool = nil
        setDrawViews(hidden: true)
        setFilterViews(hidden: true)
        setAdjustViews(hidden: true)
    }
    
    func mosaicBtnClick() {
        let isSelected = selectedTool != .mosaic
        if isSelected {
            selectedTool = .mosaic
        } else {
            selectedTool = nil
        }
        
        generateNewMosaicLayerIfAdjust()
        setDrawViews(hidden: true)
        setFilterViews(hidden: true)
        setAdjustViews(hidden: true)
    }
    
    func filterBtnClick() {
        isApplyFilter = true
        setViewOnFilter()
            selectedTool = .filter
        
        setDrawViews(hidden: true)
        setFilterViews(hidden: !isApplyFilter)
        setAdjustViews(hidden: true)
    }
    
    @objc func closeFilterView() {
        isApplyFilter = false
        setViewOnFilter()
        setFilterViews(hidden: !isApplyFilter)
    }
    
    func setViewOnFilter() {
        doneBtn.isHidden = isApplyFilter
        editToolCollectionView.isHidden = isApplyFilter
        closeBtn.isHidden = !isApplyFilter
    }
    
    func adjustBtnClick() {
        let isSelected = selectedTool != .adjust
        if isSelected {
            selectedTool = .adjust
        } else {
            selectedTool = nil
        }
        
        generateAdjustImageRef()
        setDrawViews(hidden: true)
        setFilterViews(hidden: true)
        setAdjustViews(hidden: !isSelected)
    }
    
    private func setDrawViews(hidden: Bool) {
        eraserBtn.isHidden = hidden
        eraserBtnBgBlurView.isHidden = hidden || !eraserBtn.isSelected
        eraserLineView.isHidden = hidden
        drawColorCollectionView?.isHidden = hidden
    }
    
    private func setFilterViews(hidden: Bool) {
        filterCollectionView?.isHidden = hidden
    }
    
    private func setAdjustViews(hidden: Bool) {
        adjustCollectionView?.isHidden = hidden
        adjustSlider?.isHidden = hidden
    }
    
    func changeAdjustTool(_ tool: ZLImageEditorConfiguration.AdjustTool) {
        selectedAdjustTool = tool
        
        switch tool {
        case .brightness:
            adjustSlider?.value = currentAdjustStatus.brightness
        case .contrast:
            adjustSlider?.value = currentAdjustStatus.contrast
        case .saturation:
            adjustSlider?.value = currentAdjustStatus.saturation
        }
    }
    
    @objc func doneBtnClick() {
        var editedImages: [UIImage] = []
        
        for i in 0..<editingImageCollectionView.numberOfItems(inSection: 0) {
            let indexPath = IndexPath(item: i, section: 0)
            guard let cell = editingImageCollectionView.cellForItem(at: indexPath) as? ZLEditingImageCells else {
                editingImageCollectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
                editingImageCollectionView.layoutIfNeeded()
                if let loadedCell = editingImageCollectionView.cellForItem(at: indexPath) as? ZLEditingImageCells {
                    let renderedImage = renderCell(loadedCell)
                    editedImages.append(renderedImage)
                }
                continue
            }
            let renderedImage = renderCell(cell)
            editedImages.append(renderedImage)
        }
        
        func callback() {
            dismiss(animated: animateDismiss) {
                self.editFinishBlock?(editedImages)
            }
        }
        
        callback()
    }
    
    func renderCell(_ cell: ZLEditingImageCells) -> UIImage {
        let container = cell.containerView
        return UIGraphicsImageRenderer(size: container.bounds.size).image { context in
            container.layer.render(in: context.cgContext)
        }
    }
    
    @objc func undoBtnClick() {
        mediaList[selectedIndex].actions.removeLast()
        editorManager.undoAction()
        mediaListCollectionView.reloadData()
        editingImageCollectionView.reloadData()
    }
    
    @objc func redoBtnClick() {
        let image = mediaList[selectedIndex]
        let action = image.redoActions[image.actions.count]
        mediaList[selectedIndex].actions.append(action)
        editorManager.redoAction()
        mediaListCollectionView.reloadData()
        editingImageCollectionView.reloadData()
    }
    
    @objc func tapAction(_ tap: UITapGestureRecognizer) {
        if bottomShadowView.alpha == 1 {
            setToolView(show: false)
        } else {
            setToolView(show: true)
        }
    }
    
    @objc func drawAction(_ pan: UIPanGestureRecognizer) {
        // 橡皮擦
        if selectedTool == .draw, eraserBtn.isSelected {
            eraserAction(pan)
            return
        }
        
        if selectedTool == .draw {
            let point = pan.location(in: drawingImageView)
            if pan.state == .began {
                setToolView(show: false)
            } else if pan.state == .changed {
                let path = drawPaths.last
                path?.addLine(to: point)
                drawLine()
            } else if pan.state == .cancelled || pan.state == .ended {
                setToolView(show: true, delay: 0.5)
                if let path = drawPaths.last {
                    editorManager.storeAction(.draw(path))
                }
            }
        } else if selectedTool == .mosaic {
            let point = pan.location(in: imageView)
            if pan.state == .began {
                setToolView(show: false)
                
                var actualSize = currentClipStatus.editRect.size
            } else if pan.state == .changed {
                let path = mosaicPaths.last
                path?.addLine(to: point)
                mosaicImageLayerMaskLayer?.path = path?.path.cgPath
            } else if pan.state == .cancelled || pan.state == .ended {
                setToolView(show: true, delay: 0.5)
                if let path = mosaicPaths.last {
                    editorManager.storeAction(.mosaic(path))
                }
                generateNewMosaicImage()
            }
        }
    }
    
    private func eraserAction(_ pan: UIPanGestureRecognizer) {
        // 相对于drawingImageView的point
        let point = pan.location(in: drawingImageView)
        if pan.state == .began {
            eraserCircleView.isHidden = false
            impactFeedback?.prepare()
        }
        
        if pan.state == .began || pan.state == .changed {
            var transform: CGAffineTransform = .identity
            
            let angle = ((Int(currentClipStatus.angle) % 360) + 360) % 360
            let drawingImageViewSize = drawingImageView.frame.size
            if angle == 90 {
                transform = transform.translatedBy(x: 0, y: -drawingImageViewSize.width)
            } else if angle == 180 {
                transform = transform.translatedBy(x: -drawingImageViewSize.width, y: -drawingImageViewSize.height)
            } else if angle == 270 {
                transform = transform.translatedBy(x: -drawingImageViewSize.height, y: 0)
            }
            transform = transform.concatenating(drawingImageView.transform)
            let transformedPoint = point.applying(transform)
            // 将变换后的点转换到 containerView 的坐标系
            let pointInContainerView = drawingImageView.convert(transformedPoint, to: containerView)
            eraserCircleView.center = pointInContainerView
        } else {
            eraserCircleView.isHidden = true
            if !deleteDrawPaths.isEmpty {
                editorManager.storeAction(.eraser(deleteDrawPaths))
                drawPaths.removeAll { deleteDrawPaths.contains($0) }
                deleteDrawPaths.removeAll()
                drawLine()
            }
        }
    }
    
    // 生成一个没有调整参数前的图片
    func generateAdjustImageRef() {
        editImageAdjustRef = generateNewMosaicImage(
            inputImage: editImageWithoutAdjust,
            inputMosaicImage: editImageWithoutAdjust.zl.mosaicImage()
        )
    }
    
    func adjustValueChanged(_ value: Float) {
        guard let selectedAdjustTool else {
            return
        }
        
        switch selectedAdjustTool {
        case .brightness:
            if currentAdjustStatus.brightness == value {
                return
            }
            
            currentAdjustStatus.brightness = value
        case .contrast:
            if currentAdjustStatus.contrast == value {
                return
            }
            
            currentAdjustStatus.contrast = value
        case .saturation:
            if currentAdjustStatus.saturation == value {
                return
            }
            
            currentAdjustStatus.saturation = value
        }
        
        adjustStatusChanged()
    }
    
    private func adjustStatusChanged() {
        let resultImage = editImageAdjustRef?.zl.adjust(
            brightness: currentAdjustStatus.brightness,
            contrast: currentAdjustStatus.contrast,
            saturation: currentAdjustStatus.saturation
        )
        
        guard let resultImage else { return }
        
        editImage = resultImage
        imageView.image = editImage
    }
    
    private func generateNewMosaicLayerIfAdjust() {
        defer {
            hasAdjustedImage = false
        }
        
        guard tools.contains(.mosaic), hasAdjustedImage else { return }
        generateNewMosaicImageLayer()
        
        if !mosaicPaths.isEmpty {
            generateNewMosaicImage()
        }
    }
    
    func setToolView(show: Bool, delay: TimeInterval? = nil) {
        cleanToolViewStateTimer()
        if let delay = delay {
            toolViewStateTimer = Timer.scheduledTimer(timeInterval: delay, target: ZLWeakProxy(target: self), selector: #selector(setToolViewShow_timerFunc(show:)), userInfo: ["show": show], repeats: false)
            RunLoop.current.add(toolViewStateTimer!, forMode: .common)
        } else {
            setToolViewShow_timerFunc(show: show)
        }
    }
    
    @objc private func setToolViewShow_timerFunc(show: Bool) {
        var flag = show
        if let toolViewStateTimer = toolViewStateTimer {
            let userInfo = toolViewStateTimer.userInfo as? [String: Any]
            flag = userInfo?["show"] as? Bool ?? true
            cleanToolViewStateTimer()
        }
        topShadowView.layer.removeAllAnimations()
        bottomShadowView.layer.removeAllAnimations()
        adjustSlider?.layer.removeAllAnimations()
        if flag {
            UIView.animate(withDuration: 0.25) {
                self.topShadowView.alpha = 1
                self.mediaListCollectionView.alpha = 1
                self.bottomShadowView.alpha = 1
                self.adjustSlider?.alpha = 1
            }
        } else {
            UIView.animate(withDuration: 0.25) {
                self.topShadowView.alpha = 0
                self.mediaListCollectionView.alpha = 0
                self.bottomShadowView.alpha = 0
                self.adjustSlider?.alpha = 0
            }
        }
    }
    
    private func cleanToolViewStateTimer() {
        toolViewStateTimer?.invalidate()
        toolViewStateTimer = nil
    }
    
    private func showInputTextVC(_ text: String? = nil, textColor: UIColor? = nil, font: UIFont? = nil, style: ZLInputTextStyle = .normal, completion: @escaping (String, UIColor, UIFont, UIImage?, ZLInputTextStyle) -> Void) {
        var bgImage: UIImage?
        autoreleasepool {
            // Calculate image displayed frame on the screen.
            var r = containerView.frame
            let scale = 1 / imageView.frame.width
            r.origin.x *= scale
            r.origin.y *= scale
            r.size.width *= scale
            r.size.height *= scale
            
            let isCircle = currentClipStatus.ratio?.isCircle ?? false
            bgImage = buildImage()
                .zl.clipImage(angle: currentClipStatus.angle, editRect: currentClipStatus.editRect, isCircle: isCircle)?
                .zl.clipImage(angle: 0, editRect: r, isCircle: isCircle)
        }
        
        let vc = ZLInputTextViewController(image: bgImage, text: text, font: font, textColor: textColor, style: style)
        
        vc.endInput = { text, textColor, font, image, style in
            completion(text, textColor, font, image, style)
        }
        
        vc.modalPresentationStyle = .fullScreen
        showDetailViewController(vc, sender: nil)
    }
    
    func getStickerOriginFrame(_ size: CGSize) -> CGRect {
        let originFrame = CGRect(x: 20, y: 20, width: size.width, height: size.height)
        return originFrame
    }
    
    /// Add image sticker
    func addImageStickerView(_ image: UIImage) {
        let size = ZLImageStickerView.calculateSize(image: image, width: view.frame.width)
        let originFrame = getStickerOriginFrame(size)
        
        let emojiSticker = ZLImageStickerView(
            image: image,
            originScale: 1,
            originAngle: 0,
            originFrame: originFrame)
        addSticker(emojiSticker)
      
        mediaList[selectedIndex].actions.append(.sticker(oldState: nil, newState: emojiSticker.state))
        mediaList[selectedIndex].redoActions.append(.sticker(oldState: nil, newState: emojiSticker.state))
        editorManager.storeAction(.sticker(oldState: nil, newState: emojiSticker.state))
    }
    
    /// Add text sticker
    func addTextStickersView(_ text: String, textColor: UIColor, font: UIFont, image: UIImage?, style: ZLInputTextStyle) {
        guard !text.isEmpty, let image = image else { return }
        
        let size = ZLTextStickerView.calculateSize(image: image)
        let originFrame = getStickerOriginFrame(size)
        
        let textSticker = ZLTextStickerView(
            text: text,
            textColor: textColor,
            font: font,
            style: style,
            image: image,
            originScale: 1/* / scale*/,
            originAngle: -currentClipStatus.angle,
            originFrame: originFrame
        )
        addSticker(textSticker)
      
        mediaList[selectedIndex].actions.append(.sticker(oldState: nil, newState: textSticker.state))
        mediaList[selectedIndex].redoActions.append(.sticker(oldState: nil, newState: textSticker.state))
        editorManager.storeAction(.sticker(oldState: nil, newState: textSticker.state))
    }
    
    private func addSticker(_ sticker: ZLBaseStickerView) {
        mediaList[selectedIndex].editing?.stickers.append(sticker.state)
        editingImageCollectionView.reloadData()
    }
    
    private func removeSticker(id: String?) {
        guard let id else { return }
        
        for sticker in stickersContainer.subviews.reversed() {
            guard let stickerID = (sticker as? ZLBaseStickerView)?.id,
                  stickerID == id else {
                continue
            }
            
            (sticker as? ZLBaseStickerView)?.moveToAshbin()
            
            break
        }
        
        if let stickers = mediaList[selectedIndex].editing?.stickers {
            for index in 0..<stickers.count {
                if stickers[index].id == id {
                    mediaList[selectedIndex].editing?.stickers.remove(at: index)
                }
            }
        }
    }
    
    func recalculateStickersFrame(_ oldSize: CGSize, _ oldAngle: CGFloat, _ newAngle: CGFloat) {
        let currSize = stickersContainer.frame.size
        let scale: CGFloat
        if Int(newAngle - oldAngle) % 180 == 0 {
            scale = currSize.width / oldSize.width
        } else {
            scale = currSize.height / oldSize.width
        }
        
        stickersContainer.subviews.forEach { view in
            (view as? ZLStickerViewAdditional)?.addScale(scale)
        }
    }
    
    func drawLine() {
    }
    
    private func changeFilter(_ filter: ZLFilter) {
        func adjustImage(_ image: UIImage) -> UIImage {
            guard tools.contains(.adjust), !currentAdjustStatus.allValueIsZero else {
                return image
            }
            
            return image.zl.adjust(
                brightness: currentAdjustStatus.brightness,
                contrast: currentAdjustStatus.contrast,
                saturation: currentAdjustStatus.saturation
            ) ?? image
        }
        
        currentFilter = filter
        if mediaList[selectedIndex].editing?.selectFilter != filter {
            let image = currentFilter.applier?(originalImage) ?? originalImage
            editImage = adjustImage(image)
            mediaList[selectedIndex].filteredImage = editImage
            mediaList[selectedIndex].editing?.selectFilter = filter
            editImageWithoutAdjust = image
            filterImages[currentFilter.name] = image
            editingImageCollectionView.reloadData()
        }
        
        if tools.contains(.mosaic) {
            generateNewMosaicImageLayer()
            
            if mosaicPaths.isEmpty {
                imageView.image = editImage
            } else {
                generateNewMosaicImage()
            }
        } else {
            imageView.image = editImage
        }
    }
    
    func generateNewMosaicImageLayer() {
        mosaicImage = editImage.zl.mosaicImage()
        
        mosaicImageLayer?.removeFromSuperlayer()
        
        mosaicImageLayer = CALayer()
        mosaicImageLayer?.frame = imageView.bounds
        mosaicImageLayer?.contents = mosaicImage?.cgImage
        imageView.layer.insertSublayer(mosaicImageLayer!, below: mosaicImageLayerMaskLayer)
        
        mosaicImageLayer?.mask = mosaicImageLayerMaskLayer
    }
    
    /// 传入inputImage 和 inputMosaicImage则代表仅想要获取新生成的mosaic图片
    @discardableResult
    func generateNewMosaicImage(inputImage: UIImage? = nil, inputMosaicImage: UIImage? = nil) -> UIImage? {
        let renderRect = CGRect(origin: .zero, size: originalImage.size)
        
        var midImage = UIGraphicsImageRenderer.zl.renderImage(size: originalImage.size) { format in
            format.scale = self.originalImage.scale
        } imageActions: { context in
            if inputImage != nil {
                inputImage?.draw(in: renderRect)
            } else {
                var drawImage: UIImage?
                if tools.contains(.filter), let image = filterImages[currentFilter.name] {
                    drawImage = image
                } else {
                    drawImage = originalImage
                }
                
                drawImage?.draw(at: .zero)
                if tools.contains(.adjust), !currentAdjustStatus.allValueIsZero {
                    drawImage = drawImage?.zl.adjust(
                        brightness: currentAdjustStatus.brightness,
                        contrast: currentAdjustStatus.contrast,
                        saturation: currentAdjustStatus.saturation
                    )
                }
                
                drawImage?.draw(in: renderRect)
            }
            
            mosaicPaths.forEach { path in
                context.move(to: path.startPoint)
                path.linePoints.forEach { point in
                    context.addLine(to: point)
                }
                context.setLineWidth(path.path.lineWidth / path.ratio)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setBlendMode(.clear)
                context.strokePath()
            }
        }
        
        guard let midCgImage = midImage.cgImage else { return nil }
        midImage = UIImage(cgImage: midCgImage, scale: editImage.scale, orientation: .up)
        
        let temp = UIGraphicsImageRenderer.zl.renderImage(size: originalImage.size) { format in
            format.scale = self.originalImage.scale
        } imageActions: { _ in
            // 由于生成的mosaic图片可能在边缘区域出现空白部分，导致合成后会有黑边，所以在最下面先画一张原图
            originalImage.draw(in: renderRect)
            (inputMosaicImage ?? mosaicImage)?.draw(in: renderRect)
            midImage.draw(at: .zero)
        }
        
        guard let cgi = temp.cgImage else { return nil }
        let image = UIImage(cgImage: cgi, scale: editImage.scale, orientation: .up)
        
        if inputImage != nil {
            return image
        }
        
        editImage = image
        imageView.image = image
        mosaicImageLayerMaskLayer?.path = nil
        
        return image
    }
    
    func buildImage() -> UIImage {
        let imageSize = originalImage.size
        
        let temp = UIGraphicsImageRenderer.zl.renderImage(size: editImage.size) { format in
            format.scale = self.editImage.scale
        } imageActions: { context in
            editImage.draw(at: .zero)
            drawingImageView.image?.draw(in: CGRect(origin: .zero, size: imageSize))
            
            if !stickersContainer.subviews.isEmpty {
                let scale = /*self.imageSize.width*/1 / stickersContainer.frame.width
                stickersContainer.subviews.forEach { view in
                    (view as? ZLStickerViewAdditional)?.resetState()
                }
                context.concatenate(CGAffineTransform(scaleX: scale, y: scale))
                stickersContainer.layer.render(in: context)
                context.concatenate(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            }
        }
        
        guard let cgi = temp.cgImage else {
            return editImage
        }
        return UIImage(cgImage: cgi, scale: editImage.scale, orientation: .up)
    }
    
    func finishClipDismissAnimate() {
        UIView.animate(withDuration: 0.1) {
            self.topShadowView.alpha = 1
            self.mediaListCollectionView.alpha = 1
            self.bottomShadowView.alpha = 1
            self.adjustSlider?.alpha = 1
        }
    }
}

extension ZLEditImageViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard imageStickerContainerIsHidden, fontChooserContainerIsHidden else {
            return false
        }
        if gestureRecognizer is UITapGestureRecognizer {
            if bottomShadowView.alpha == 1 {
                let p = gestureRecognizer.location(in: view)
                let convertP = bottomShadowView.convert(p, from: view)
                for subview in bottomShadowView.subviews {
                    if !subview.isHidden,
                       subview.alpha != 0,
                       subview.frame.contains(convertP) {
                        return false
                    }
                }
                return true
            } else {
                return true
            }
        } else if gestureRecognizer is UIPanGestureRecognizer {
            guard let st = selectedTool else {
                return false
            }
            return (st == .draw || st == .mosaic) && !isScrolling
        }
        
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view?.isDescendant(of: mediaListCollectionView) == true {
            return false
        }
        return true
    }
}

// MARK: scroll view delegate

extension ZLEditImageViewController: UIScrollViewDelegate {
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return containerView
    }
    
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let offsetX = (scrollView.frame.width > scrollView.contentSize.width) ? (scrollView.frame.width - scrollView.contentSize.width) * 0.5 : 0
        let offsetY = (scrollView.frame.height > scrollView.contentSize.height) ? (scrollView.frame.height - scrollView.contentSize.height) * 0.5 : 0
        containerView.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX, y: scrollView.contentSize.height * 0.5 + offsetY)
    }
    
    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        isScrolling = false
    }
}

extension ZLEditImageViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        if collectionView == emojiStickerPickerView.collectionView {
            return viewModel.numberOfSections()
        } else {
            return 1
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == mediaListCollectionView {
            return mediaList.count
        } else if collectionView == editingImageCollectionView {
            return mediaList.count
        }else if collectionView == editToolCollectionView {
            return tools.count
        } else if collectionView == drawColorCollectionView {
            return drawColors.count
        } else if collectionView == filterCollectionView {
            return thumbnailFilterImages.count
        } else if collectionView == emojiStickerPickerView.collectionView {
            return viewModel.numberOfItems(in: section)
        } else {
            return adjustTools.count
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == mediaListCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLMediaListCell.zl.identifier, for: indexPath) as! ZLMediaListCell
            cell.image.image = mediaList[indexPath.row].image
            cell.setEditingView(isEditing: indexPath.row == selectedIndex)
            return cell
        } else if collectionView == editingImageCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLEditingImageCells.zl.identifier, for: indexPath) as! ZLEditingImageCells
            cell.delegate = self
            cell.setImageView(image: mediaList[indexPath.row])
            return cell
        } else if collectionView == editToolCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLEditToolCell.zl.identifier, for: indexPath) as! ZLEditToolCell
            
            let toolType = tools[indexPath.row]
            cell.icon.isHighlighted = false
            cell.toolType = toolType
            return cell
        } else if collectionView == drawColorCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLDrawColorCell.zl.identifier, for: indexPath) as! ZLDrawColorCell
            
            let c = drawColors[indexPath.row]
            cell.color = c
            if c == currentDrawColor, !eraserBtn.isSelected {
                cell.bgBlackView.layer.transform = CATransform3DMakeScale(1.2, 1.2, 1)
            } else {
                cell.bgBlackView.layer.transform = CATransform3DIdentity
            }
            
            return cell
        } else if collectionView == filterCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLFilterImageCell.zl.identifier, for: indexPath) as! ZLFilterImageCell
            
            let image = thumbnailFilterImages[indexPath.row]
            let filter = ZLImageEditorConfiguration.default().filters[indexPath.row]
            
            cell.nameLabel.text = filter.name
            cell.imageView.image = image
            
            if currentFilter === filter {
                cell.nameLabel.textColor = .zl.toolTitleTintColor
            } else {
                cell.nameLabel.textColor = .zl.toolTitleNormalColor
            }
            
            return cell
        } else if collectionView == emojiStickerPickerView.collectionView {
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCollectionViewCell.identifier, for: indexPath) as? EmojiCollectionViewCell
            else { return UICollectionViewCell() }
            
            cell.configure(with: viewModel.emoji(at: indexPath))
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLAdjustToolCell.zl.identifier, for: indexPath) as! ZLAdjustToolCell
            
            let tool = adjustTools[indexPath.row]
            
            cell.imageView.isHighlighted = false
            cell.adjustTool = tool
            let isSelected = tool == selectedAdjustTool
            cell.imageView.isHighlighted = isSelected
            
            if isSelected {
                cell.nameLabel.textColor = .zl.toolTitleTintColor
            } else {
                cell.nameLabel.textColor = .zl.toolTitleNormalColor
            }
            return cell
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == mediaListCollectionView {
            selectedIndex = indexPath.row
            mediaListCollectionView.reloadData()
            selectImage()
        } else if collectionView == editToolCollectionView {
            let toolType = tools[indexPath.row]
            switch toolType {
            case .draw:
                drawBtnClick()
            case .clip:
                clipBtnClick()
            case .imageSticker:
                imageStickerBtnClick(show: true)
            case .textSticker:
                textStickerBtnClick()
            case .mosaic:
                mosaicBtnClick()
            case .filter:
                filterBtnClick()
            case .adjust:
                adjustBtnClick()
            }
        } else if collectionView == drawColorCollectionView {
            currentDrawColor = drawColors[indexPath.row]
            switchEraserBtnStatus(false, reloadData: false)
        } else if collectionView == filterCollectionView {
            let filter = ZLImageEditorConfiguration.default().filters[indexPath.row]
            changeFilter(filter)
        } else if collectionView == emojiStickerPickerView.collectionView {
            collectionView.deselectItem(at: indexPath, animated: true)
            viewModel.selectedEmoji.value = viewModel.emoji(at: indexPath)
            getEmojiSticker(text: viewModel.selectedEmoji.value)
        } else {
            let tool = adjustTools[indexPath.row]
            if tool != selectedAdjustTool {
                changeAdjustTool(tool)
            }
        }
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        collectionView.reloadData()
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard !isDraggingSticker else { return }
        if scrollView == editingImageCollectionView {
            if let indexPath = editingImageCollectionView.indexPathsForVisibleItems.first {
                selectedIndex = indexPath.row
                selectImage()
                mediaListCollectionView.scrollToItem(at: IndexPath(row: selectedIndex, section: 0), at: .centeredHorizontally, animated: true)
                mediaListCollectionView.reloadData()
            }
        }
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !isDraggingSticker else { return }
        if !decelerate && scrollView == editingImageCollectionView {
            if let indexPath = editingImageCollectionView.indexPathsForVisibleItems.first {
                selectedIndex = indexPath.row
                selectImage()
                mediaListCollectionView.scrollToItem(at: IndexPath(row: selectedIndex, section: 0), at: .centeredHorizontally, animated: true)
                mediaListCollectionView.reloadData()
            }
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if collectionView == emojiStickerPickerView.collectionView {
            switch kind {
            case UICollectionView.elementKindSectionHeader:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: EmojiCollectionViewHeader.identifier, for: indexPath) as? EmojiCollectionViewHeader
                else { return UICollectionReusableView() }
                
                sectionHeader.configure(with: viewModel.sectionHeaderViewModel(for: indexPath.section))
                sectionHeader.closeBtn.addTarget(self, action: #selector(closeEmojiPicker), for: .touchUpInside)
                return sectionHeader
            default:
                return UICollectionReusableView()
            }
        }
        return UICollectionReusableView()
    }
}

// MARK: undo & redo
extension ZLEditImageViewController: ZLEditorManagerDelegate {
    func editorManager(_ manager: ZLEditorManager, didUpdateActions actions: [ZLEditorAction], redoActions: [ZLEditorAction]) {
        undoBtn.isEnabled = !actions.isEmpty
        redoBtn.isEnabled = actions.count != redoActions.count
    }
    
    func editorManager(_ manager: ZLEditorManager, undoAction action: ZLEditorAction) {
        switch action {
        case let .draw(path):
            undoDraw(path)
        case let .eraser(paths):
            undoEraser(paths)
        case let .clip(oldStatus, _):
            undoOrRedoClip(oldStatus)
        case let .sticker(oldState, newState):
            undoSticker(oldState, newState)
        case let .mosaic(path):
            undoMosaic(path)
        case let .filter(oldFilter, _):
            undoOrRedoFilter(oldFilter)
        case let .adjust(oldStatus, _):
            undoOrRedoAdjust(oldStatus)
        }
    }
    
    func editorManager(_ manager: ZLEditorManager, redoAction action: ZLEditorAction) {
        switch action {
        case let .draw(path):
            redoDraw(path)
        case let .eraser(paths):
            redoEraser(paths)
        case let .clip(_, newStatus):
            undoOrRedoClip(newStatus)
        case let .sticker(oldState, newState):
            redoSticker(oldState, newState)
        case let .mosaic(path):
            redoMosaic(path)
        case let .filter(_, newFilter):
            undoOrRedoFilter(newFilter)
        case let .adjust(_, newStatus):
            undoOrRedoAdjust(newStatus)
        }
    }
    
    private func undoDraw(_ path: ZLDrawPath) {
        drawPaths.removeLast()
        drawLine()
    }
    
    private func redoDraw(_ path: ZLDrawPath) {
        drawPaths.append(path)
        drawLine()
    }
    
    private func undoEraser(_ paths: [ZLDrawPath]) {
        paths.forEach { $0.willDelete = false }
        drawPaths.append(contentsOf: paths)
        drawPaths = drawPaths.sorted { $0.index < $1.index }
        drawLine()
    }
    
    private func redoEraser(_ paths: [ZLDrawPath]) {
        drawPaths.removeAll { paths.contains($0) }
        drawLine()
    }
    
    private func undoOrRedoClip(_ status: ZLClipStatus) {
        clipImage(status: status)
        preClipStatus = status
    }
    
    private func undoMosaic(_ path: ZLMosaicPath) {
        mosaicPaths.removeLast()
        generateNewMosaicImage()
    }
    
    private func redoMosaic(_ path: ZLMosaicPath) {
        mosaicPaths.append(path)
        generateNewMosaicImage()
    }
    
    private func undoSticker(_ oldState: ZLBaseStickertState?, _ newState: ZLBaseStickertState?) {
        guard let oldState else {
            removeSticker(id: newState?.id)
            return
        }
        
        removeSticker(id: oldState.id)
        if let sticker = ZLBaseStickerView.initWithState(oldState) {
            addSticker(sticker)
        }
    }
    
    private func redoSticker(_ oldState: ZLBaseStickertState?, _ newState: ZLBaseStickertState?) {
        guard let newState else {
            removeSticker(id: oldState?.id)
            return
        }
        
        removeSticker(id: newState.id)
        if let sticker = ZLBaseStickerView.initWithState(newState) {
            addSticker(sticker)
        }
    }
    
    private func undoOrRedoFilter(_ filter: ZLFilter?) {
        guard let filter else { return }
        changeFilter(filter)
        
        let filters = ZLImageEditorConfiguration.default().filters
        
        guard let filterCollectionView,
              let index = filters.firstIndex(where: { $0.name == filter.name }) else {
            return
        }
        
        let indexPath = IndexPath(row: index, section: 0)
        filterCollectionView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredHorizontally)
        filterCollectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        filterCollectionView.reloadData()
    }
    
    private func undoOrRedoAdjust(_ status: ZLAdjustStatus) {
        var adjustTool: ZLImageEditorConfiguration.AdjustTool?
        
        if currentAdjustStatus.brightness != status.brightness {
            adjustTool = .brightness
        } else if currentAdjustStatus.contrast != status.contrast {
            adjustTool = .contrast
        } else if currentAdjustStatus.saturation != status.saturation {
            adjustTool = .saturation
        }
        
        currentAdjustStatus = status
        preAdjustStatus = status
        adjustStatusChanged()
        
        guard let adjustTool else { return }
        
        changeAdjustTool(adjustTool)
        
        guard let adjustCollectionView,
              let index = adjustTools.firstIndex(where: { $0 == adjustTool }) else {
            return
        }
        
        let indexPath = IndexPath(row: index, section: 0)
        adjustCollectionView.selectItem(at: indexPath, animated: true, scrollPosition: .centeredHorizontally)
        adjustCollectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        adjustCollectionView.reloadData()
    }
}

// MARK: 手势可透传的自定义view
public class ZLPassThroughView: UIView {
    var findResponderSticker: ((CGPoint) -> UIView?)?
    
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else {
            return super.hitTest(point, with: event)
        }
        
        for view in subviews.reversed() {
            let point = convert(point, to: view)
            if !view.isHidden,
               view.alpha != 0,
               view.bounds.contains(point) {
                return view.hitTest(point, with: event)
            }
        }
        
        if let sticker = findResponderSticker?(convert(point, to: superview)) {
            return sticker.hitTest(point, with: event)
        }
        
        return super.hitTest(point, with: event)
    }
}

extension ZLEditImageViewController: ZLEditingImageStickerDelegate {
    func stickerBeginOperation(_ sticker: ZLBaseStickerView) {
        isDraggingSticker = true
        editingImageCollectionView.isScrollEnabled = false
        preStickerState = sticker.state
    }
    
    func stickerEndOperation(_ sticker: ZLBaseStickerView, point:CGPoint) {
        setToolView(show: true)
        
        var endState: ZLBaseStickertState? = sticker.state
        if let list = mediaList[selectedIndex].editing?.stickers {
            for index in 0..<list.count {
                if list[index].id == sticker.state.id {
                    if let stickerRect = mediaList[selectedIndex].editing?.stickers[index] {
                        let rect = CGRect(x: point.x,
                                          y: point.y,
                                          width: stickerRect.originFrame.width,
                                          height: stickerRect.originFrame.height)
                        stickerRect.originFrame = rect
                        stickerRect.gesRotation = sticker.gesRotation
                        stickerRect.gesScale = sticker.gesScale
                        endState = stickerRect
                        mediaList[selectedIndex].editing?.stickers[index] = stickerRect
                        
                        mediaList[selectedIndex].actions.append(.sticker(oldState: preStickerState, newState: endState))
                        mediaList[selectedIndex].redoActions.append(.sticker(oldState: preStickerState, newState: endState))
                        editorManager.storeAction(.sticker(oldState: preStickerState, newState: endState))
                        preStickerState = nil
                        editingImageCollectionView.reloadData()
                        isDraggingSticker = false
                        editingImageCollectionView.isScrollEnabled = true
                    }
                }
            }
        }
    }
    
    func showInputTextVC(_ textSticker: ZLTextStickerView, editText text: String) {
        showInputTextVC(text, textColor: textSticker.textColor, font: textSticker.font, style: textSticker.style) { text, textColor, font, image, style in
            guard let image = image, !text.isEmpty else {
                textSticker.moveToAshbin()
                return
            }
            
            textSticker.startTimer()
            guard textSticker.text != text || textSticker.textColor != textColor || textSticker.style != style || textSticker.font != font else {
                return
            }
            textSticker.text = text
            textSticker.textColor = textColor
            textSticker.style = style
            textSticker.image = image
            textSticker.font = font
            let newSize = ZLTextStickerView.calculateSize(image: image)
            textSticker.changeSize(to: newSize)
        }
    }
    
    func stickerDidDelete(_ sticker: ZLBaseStickerView) {
        if let stickers = mediaList[selectedIndex].editing?.stickers {
            for index in 0..<stickers.count {
                if stickers[index].id == sticker.id {
                    mediaList[selectedIndex].editing?.stickers.remove(at: index)
                    editingImageCollectionView.reloadData()
                }
            }
        }
    }
}

//MARK: - EmojiPickerViewDelegate
extension ZLEditImageViewController: EmojiPickerViewDelegate {
    
    func didChoiceEmojiCategory(at index: Int) {
        feedbackGenerator?.impactOccurred()
        viewModel.selectedEmojiCategoryIndex.value = index
    }
}


// MARK: - UIAdaptivePresentationControllerDelegate
extension ZLEditImageViewController: UIAdaptivePresentationControllerDelegate {
    
    public func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}
