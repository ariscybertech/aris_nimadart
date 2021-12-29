import 'dart:typed_data';
import "binary_reader.dart";
import "actor_node.dart";
import "math/mat2d.dart";
import "math/vec2d.dart";
import "actor.dart";
import "actor_component.dart";
import "actor_bone_base.dart";

enum BlendModes
{
	Normal,
	Multiply,
	Screen,
	Additive
}

class BoneConnection
{
	int boneIdx;
	ActorNode node;
	Mat2D bind = new Mat2D();
	Mat2D inverseBind = new Mat2D();
}

class ActorImage extends ActorNode
{
	// Editor set draw index.
	int drawOrder = 0;
	// Computed draw index in the image list.
	int drawIndex = 0;
	BlendModes _blendMode;
	int _textureIndex = -1;
	Float32List _vertices;
	Uint16List _triangles;
	int _vertexCount = 0;
	int _triangleCount = 0;
	Float32List _animationDeformedVertices;
	bool isVertexDeformDirty = false;

	List<BoneConnection> _boneConnections;
	Float32List _boneMatrices;

	int get connectedBoneCount
	{
		return _boneConnections == null ? 0 : _boneConnections.length;
	}

	List<BoneConnection> get boneConnections
	{
		return _boneConnections;
	}

	int get textureIndex
	{
		return _textureIndex;
	}

	BlendModes get blendMode
	{
		return _blendMode;
	}


	int get vertexCount
	{
		return _vertexCount;
	}

	int get triangleCount
	{
		return _triangleCount;
	}

	Uint16List get triangles
	{
		return _triangles;
	}
	
	Float32List get vertices
	{
		return _vertices;
	}

	int get vertexPositionOffset
	{
		return 0;
	}

	int get vertexUVOffset
	{
		return 2;
	}

	int get vertexBoneIndexOffset
	{
		return 4;
	}

	int get vertexBoneWeightOffset
	{
		return 8;
	}

	int get vertexStride
	{
		return _boneConnections != null ? 12 : 4;
	}

	bool get isSkinned
	{
		return _boneConnections != null;
	}

	bool get doesAnimationVertexDeform
	{
		return _animationDeformedVertices != null;
	}

	set doesAnimationVertexDeform(bool value)
	{
		if(value)
		{
			if(_animationDeformedVertices == null || _animationDeformedVertices.length != _vertexCount * 2)
			{
				_animationDeformedVertices = new Float32List(vertexCount*2);
				// Copy the deform verts from the rig verts.
				int writeIdx = 0;
				int readIdx = 0;
				int readStride = vertexStride;
				for(int i = 0; i < _vertexCount; i++)
				{
					_animationDeformedVertices[writeIdx++] = _vertices[readIdx];
					_animationDeformedVertices[writeIdx++] = _vertices[readIdx+1];
					readIdx += readStride;
				}
			}
		}
		else
		{
			_animationDeformedVertices = null;
		}
	}

	Float32List get animationDeformedVertices
	{
		return _animationDeformedVertices;
	}	

	ActorImage();

	void disposeGeometry()
	{
		// Delete vertices only if we do not vertex deform at runtime.
		if(_animationDeformedVertices == null)
		{
			_vertices = null;
		}
		_triangles = null;
	}

	// We don't do this at initialization as some engines (like Unity)
	// don't need us to handle the bone matrix transforms ourselves.
	// This helps keep memory a little lower when this code runs in those engines.
	void instanceBoneMatrices()
	{
		if(_boneMatrices == null)
		{
			int numConnectedBones = _boneConnections.length;
			_boneMatrices = new Float32List((numConnectedBones+1)*6);
			// First bone transform is always identity.
			_boneMatrices[0] = 1.0;
			_boneMatrices[1] = 0.0;
			_boneMatrices[2] = 0.0;
			_boneMatrices[3] = 1.0;
			_boneMatrices[4] = 0.0;
			_boneMatrices[5] = 0.0;
		}
	}

	Float32List get boneInfluenceMatrices
	{
		instanceBoneMatrices();

		Mat2D mat = new Mat2D();
		int bidx = 6;
		for(BoneConnection bc in _boneConnections)
		{
			Mat2D.multiply(mat, bc.node.worldTransform, bc.inverseBind);

			_boneMatrices[bidx++] = mat[0];
			_boneMatrices[bidx++] = mat[1];
			_boneMatrices[bidx++] = mat[2];
			_boneMatrices[bidx++] = mat[3];
			_boneMatrices[bidx++] = mat[4];
			_boneMatrices[bidx++] = mat[5];
		}

		return _boneMatrices;
	}

	Float32List get boneTransformMatrices
	{
		instanceBoneMatrices();

		int bidx = 6;
		for(BoneConnection bc in _boneConnections)
		{
			Mat2D mat = bc.node.worldTransform;

			_boneMatrices[bidx++] = mat[0];
			_boneMatrices[bidx++] = mat[1];
			_boneMatrices[bidx++] = mat[2];
			_boneMatrices[bidx++] = mat[3];
			_boneMatrices[bidx++] = mat[4];
			_boneMatrices[bidx++] = mat[5];
		}

		return _boneMatrices;
	}

	static ActorImage read(Actor actor, BinaryReader reader, ActorImage node)
	{
		if(node == null)
		{
			node = new ActorImage();
		}
		
		ActorNode.read(actor, reader, node);

		bool isVisible = reader.readUint8() != 0;
		if(isVisible)
		{
			int blendModeId = reader.readUint8();
			BlendModes blendMode = BlendModes.Normal;
			switch(blendModeId)
			{
				case 0:
					blendMode = BlendModes.Normal;
					break;
				case 1:
					blendMode = BlendModes.Multiply;
					break;
				case 2:
					blendMode = BlendModes.Screen;
					break;
				case 3:
					blendMode = BlendModes.Additive;
					break;
			}
			node._blendMode = blendMode;
			node.drawOrder = reader.readUint16();
			node._textureIndex = reader.readUint8();

			int numConnectedBones = reader.readUint8();
			if(numConnectedBones != 0)
			{
				node._boneConnections = new List<BoneConnection>(numConnectedBones);

				for(int i = 0; i < numConnectedBones; i++)
				{
					BoneConnection bc = new BoneConnection();
					bc.boneIdx = reader.readUint16();
					reader.readFloat32Array(bc.bind.values, 6, 0);
					Mat2D.invert(bc.inverseBind, bc.bind);
					node._boneConnections[i] = bc;
				}

				Mat2D worldOverride = new Mat2D();
				reader.readFloat32Array(worldOverride.values, 6, 0);
				node.worldTransformOverride = worldOverride;
			}

			int numVertices = reader.readUint32();
			int vertexStride = numConnectedBones > 0 ? 12 : 4;
			node._vertexCount = numVertices;
			node._vertices = new Float32List(numVertices * vertexStride);
			reader.readFloat32Array(node._vertices, node._vertices.length, 0);
			
			int numTris = reader.readUint32();
			node._triangles = new Uint16List(numTris*3);
			node._triangleCount = numTris;
			reader.readUint16Array(node._triangles, node._triangles.length, 0);
		}

		return node;
	}

	void resolveComponentIndices(List<ActorComponent> components)
	{
		super.resolveComponentIndices(components);
		if(_boneConnections != null)
		{
			for(int i = 0; i < _boneConnections.length; i++)
			{
				BoneConnection bc = _boneConnections[i];
				bc.node = components[bc.boneIdx] as ActorNode;
				ActorBoneBase bone = bc.node as ActorBoneBase;
				bone.isConnectedToImage = true;
			}	
		}
	}

	ActorComponent makeInstance(Actor resetActor)
	{
		ActorImage instanceNode = new ActorImage();
		instanceNode.copyImage(this, resetActor);
		return instanceNode;
	}

	void copyImage(ActorImage node, Actor resetActor)
	{
		copyNode(node, resetActor);

		drawOrder = node.drawOrder;
		_blendMode = node._blendMode;
		_textureIndex = node._textureIndex;
		_vertexCount = node._vertexCount;
		_triangleCount = node._triangleCount;
		_vertices = node._vertices;
		_triangles = node._triangles;
		if(node._animationDeformedVertices != null)
		{
			_animationDeformedVertices = new Float32List.fromList(node._animationDeformedVertices);
		}

		if(node._boneConnections != null)
		{
			_boneConnections = new List<BoneConnection>(node._boneConnections.length);
			for(int i = 0; i < node._boneConnections.length; i++)
			{
				BoneConnection bc = new BoneConnection();
				bc.boneIdx = node._boneConnections[i].boneIdx;
				Mat2D.copy(bc.bind, node._boneConnections[i].bind);
				Mat2D.copy(bc.inverseBind, node._boneConnections[i].inverseBind);
				_boneConnections[i] = bc;
			} 
		}
	}

	void transformBind(Mat2D xform)
	{
		if(_boneConnections != null)
		{
			for(BoneConnection bc in _boneConnections)
			{
				Mat2D.multiply(bc.bind, xform, bc.bind);
				Mat2D.invert(bc.inverseBind, bc.bind);
			}
		}
	}

	Float32List makeVertexPositionBuffer()
	{
		return new Float32List(_vertexCount * 2);
	}

	Float32List makeVertexUVBuffer()
	{
		return new Float32List(_vertexCount * 2);
	}

	void transformDeformVertices(Mat2D wt)
	{
		if(_animationDeformedVertices == null)
		{
			return;
		}
		
		Float32List fv = _animationDeformedVertices;

		int vidx = 0;
		for(int j = 0; j < _vertexCount; j++)
		{
			double x = fv[vidx];
			double y = fv[vidx+1];

			fv[vidx] = wt[0] * x + wt[2] * y + wt[4];
			fv[vidx+1] = wt[1] * x + wt[3] * y + wt[5];

			vidx += 2;
		}
	}

	void updateVertexUVBuffer(Float32List buffer)
	{
		int readIdx = vertexUVOffset;
		int writeIdx = 0;
		int stride = vertexStride;

		Float32List v = _vertices;
		for(int i = 0; i < _vertexCount; i++)
		{
			buffer[writeIdx++] = v[readIdx];
			buffer[writeIdx++] = v[readIdx+1];
			readIdx += stride;
		}
	}

	void updateVertexPositionBuffer(Float32List buffer, bool isSkinnedDeformInWorld)
	{
		Mat2D worldTransform = this.worldTransform;
		int readIdx = 0;
		int writeIdx = 0;

		Float32List v = _animationDeformedVertices != null ? _animationDeformedVertices : _vertices;
		int stride = _animationDeformedVertices != null ? 2 : vertexStride;
		
		if(isSkinned)
		{
			Float32List boneTransforms = boneInfluenceMatrices;

			//Mat2D inverseWorldTransform = Mat2D.Invert(new Mat2D(), worldTransform);
			Float32List influenceMatrix = new Float32List.fromList([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
			int boneIndexOffset = vertexBoneIndexOffset;
			int weightOffset = vertexBoneWeightOffset;
			for(int i = 0; i < _vertexCount; i++)
			{
				double x = v[readIdx];
				double y = v[readIdx+1];

				double px, py;

				if(_animationDeformedVertices != null && isSkinnedDeformInWorld)
				{
					px = x;
					py = y;
				}
				else
				{
					px = worldTransform[0] * x + worldTransform[2] * y + worldTransform[4];
					py = worldTransform[1] * x + worldTransform[3] * y + worldTransform[5];
				}

				influenceMatrix[0] = influenceMatrix[1] = influenceMatrix[2] = influenceMatrix[3] = influenceMatrix[4] = influenceMatrix[5] = 0.0;

				for(int wi = 0; wi < 4; wi++)
				{
					int boneIndex = _vertices[boneIndexOffset+wi].toInt();
					double weight = _vertices[weightOffset+wi];

					int boneTransformIndex = boneIndex*6;
					for(int j = 0; j < 6; j++)
					{
						influenceMatrix[j] += boneTransforms[boneTransformIndex+j] * weight;
					}
				}

				x = influenceMatrix[0] * px + influenceMatrix[2] * py + influenceMatrix[4];
				y = influenceMatrix[1] * px + influenceMatrix[3] * py + influenceMatrix[5];

				readIdx += stride;
				boneIndexOffset += vertexStride;
				weightOffset += vertexStride;

				buffer[writeIdx++] = x;
				buffer[writeIdx++] = y;
			}
		}
		else
		{
			Vec2D tempVec = new Vec2D();
			for(int i = 0; i < _vertexCount; i++)
			{
				tempVec[0] = v[readIdx];
				tempVec[1] = v[readIdx+1];
				Vec2D.transformMat2D(tempVec, tempVec, worldTransform);
				readIdx += stride;

				buffer[writeIdx++] = tempVec[0];
				buffer[writeIdx++] = tempVec[1];
			}
		}
	}
}