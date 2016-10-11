//
//  Audio3DVisualizer.swift
//  Audio3DVisualizer
//
//  Created by Jonathan Ritchey on 7/23/16.
//  Copyright (c) 2016 Jonathan Ritchey. All rights reserved.
//

import UIKit
import QuartzCore
import SceneKit

class Audio3DVisualizer: UIViewController {

    var scnView: SCNView?
    var scnScene: SCNScene?
    let camera = Camera()
    let grid = Grid()
    let frequencyBands = FrequencyBands()
    var superpowered: Superpowered?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupAudio()
        setupView()
        setupScene()
        camera.setup(scene: scnScene)
        grid.setup(scene: scnScene)
        frequencyBands.setup(view: view)
        addGestureRecognizer()
    }
    
    func setupAudio() {
        superpowered = Superpowered()
    }
    
    func renderFrame() {
        let frequencies = UnsafeMutablePointer<Float>.allocate(capacity: FREQ_BANDS)
        superpowered?.getFrequencies(frequencies)
        frequencyBands.render(frequencies, yPosition: view.frame.size.height - 40)
        grid.render(frequencies, frequencyBands: frequencyBands)
        frequencies.deallocate(capacity: FREQ_BANDS)
    }

    func addGestureRecognizer() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView?.addGestureRecognizer(tapGesture)
    }
    
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        grid.handleTap()
    }
    
    override var shouldAutorotate : Bool {
        return true
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    func setupView() {
        scnView = self.view as? SCNView
        scnView?.showsStatistics = true
        scnView?.allowsCameraControl = true
        scnView?.autoenablesDefaultLighting = true
        scnView?.delegate = self
        scnView?.isPlaying = true
    }
    
    func setupScene() {
        scnScene = SCNScene()
        scnView?.scene = scnScene
    }
}

extension Audio3DVisualizer: SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        renderFrame()
    }
}

// MARK: - Grid
extension Audio3DVisualizer {
    class Grid {
        var gridNode = SCNNode()
        var grid: [SCNNode] = []
        enum VisualizationType {
            case rectangle
            case spiral
        }
        var visualizationType = VisualizationType.spiral
        func render(_ frequencies: UnsafeMutablePointer<Float>, frequencyBands: FrequencyBands) {
            for n in 0..<FREQ_BANDS where n < grid.count {
                let amt = Float(frequencies[n] * 200)
                grid[n].scale = SCNVector3(1, amt*2.0, 1)
                grid[n].position.y = amt
                
                let volume = frequencyBands.volumeInBand[n]
                let scaledVolume = volume * 0.8
                let newColor = UIColor(red: 0.2 + frequencyBands.colorByBandRed[n] * scaledVolume,
                                       green: 0.2 + frequencyBands.colorByBandGreen[n] * scaledVolume,
                                       blue: 0.2 + frequencyBands.colorByBandBlue[n] * scaledVolume,
                                       alpha: 1.0)
                grid[n].geometry?.materials.first?.diffuse.contents = newColor
                grid[n].geometry?.materials.first?.emission.contents = newColor
            }
        }
        
        func setup(scene: SCNScene?) {
            for _ in 0..<FREQ_BANDS {
                let node = createCube(width: 1.0, length: 1.0, position: SCNVector3(0,0,0))
                grid.append(node)
                gridNode.addChildNode(node)
            }
            switch visualizationType {
            case .rectangle:
                configRectangle()
            case .spiral:
                configSpiral()
            }
            setupAutoRotation()
            scene?.rootNode.addChildNode(gridNode)
        }
        
        func handleTap() {
            if visualizationType == .spiral {
                visualizationType = .rectangle
                configRectangle()
            } else {
                visualizationType = .spiral
                configSpiral()
            }
        }
        
        func configRectangle() {
            let gridWidth = 32
            let gridDepth = FREQ_BANDS / gridWidth
            for i in 0..<FREQ_BANDS {
                let ax = -gridWidth/2 + i % gridWidth
                let az = Int(i / gridWidth) - gridDepth / 2
                grid[i].position.x = Float(ax)
                grid[i].position.y = 0
                grid[i].position.z = Float(-az)
            }
        }
        
        func configSpiral() {
            for i in 0..<FREQ_BANDS {
                let r = Float(i) / 20.0
                let s = Float(i) / 100.0
                let x = s * cos(r)
                let z = s * sin(r)
                grid[i].position.x = Float(x)
                grid[i].position.y = 0
                grid[i].position.z = Float(z)
            }
        }
        
        func createCube(width: CGFloat, length: CGFloat, position: SCNVector3) -> SCNNode {
            var geometry: SCNGeometry
            geometry = SCNBox(width: width, height: 1.0, length: length, chamferRadius: 0.3)
            let geometryNode = SCNNode(geometry: geometry)
            geometryNode.position = position
            return geometryNode
        }
        
        func setupAutoRotation() {
            gridNode.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 2*CGFloat(M_PI), z: 0, duration: 30)))
        }
    }
}

// MARK: - Camera
extension Audio3DVisualizer {
    class Camera {
        var cameraNode = SCNNode()
        func setup(scene: SCNScene?) {
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.zFar = 1000
            cameraNode.position = SCNVector3(x: 0, y: 0, z: 50)
            scene?.rootNode.addChildNode(cameraNode)
        }
    }
}

// MARK: - 2D Frequency Bands
extension Audio3DVisualizer {
    class FrequencyBands {
        var volumeInBand: [CGFloat] = [] // 0 to 1.0
        var colorByBand: [UIColor] = []
        var colorByBandRed: [CGFloat] = []
        var colorByBandGreen: [CGFloat] = []
        var colorByBandBlue: [CGFloat] = []
        var layers:[CALayer] = []
        
        func render(_ frequencies: UnsafeMutablePointer<Float>, yPosition: CGFloat) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0)
            CATransaction.setDisableActions(true)
            // Set the dimension of every frequency bar.
            let width:CGFloat = 320.0 / CGFloat(NUM_BANDS)
            var frame:CGRect = CGRect(x: 20, y: 0, width: width, height: 0)
            for n in 0..<FREQ_BANDS {
                frame.size.height = 4 + CGFloat(frequencies[n]) * 4000
                frame.origin.y = yPosition - frame.size.height
                layers[n].frame = frame
                frame.origin.x += width
                
                let amt = Float(frequencies[n] * 200)
                
                var volume = CGFloat(amt) / 5.0
                volume = min(1, volume)
                volumeInBand[n] = volume
            }
            CATransaction.commit()
        }
        
        func setup(view: UIView) {
            setupLayers(view: view)
            setupBands()
        }
        
        func setupLayers(view: UIView) {
            for n in 0..<FREQ_BANDS {
                let color = colorForBand(n)
                let newColor = UIColor(red: 0.5 + color.components.red * 0.5,
                                       green: 0.5 + color.components.green * 0.5,
                                       blue: 0.5 + color.components.blue * 0.5, alpha: 1.0)
                let newCGColor = newColor.cgColor
                layers.append(CALayer())
                layers[n].backgroundColor = newCGColor
                layers[n].frame = CGRect.zero
                view.layer.addSublayer(layers[n])
            }
        }

        func setupBands() {
            for n in 0..<FREQ_BANDS {
                let color = colorForBand(n)
                volumeInBand.append(0)
                colorByBand.append(color)
                colorByBandRed.append(color.components.red)
                colorByBandGreen.append(color.components.green)
                colorByBandBlue.append(color.components.blue)
            }
        }
        
        func colorForBand(_ n: Int) -> UIColor {
            let range = CGFloat(0.8)
            let t = CGFloat(n) / CGFloat(FREQ_BANDS)
            return UIColor(hue: t * range, saturation: 1.0, brightness: 1.0, alpha: 1.0)
        }
    }
}

extension UIColor {
    var components:(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r,g,b,a)
    }
}
