require "../cdp"
require "json"
require "time"

require "../dom/dom"
require "../page/page"
require "../runtime/runtime"

require "./types"
require "./events"

#
@[Experimental]
module Cdp::Accessibility
  @[Experimental]
  struct GetPartialAXTreeResult
    include JSON::Serializable
    @[JSON::Field(key: "nodes", emit_null: false)]
    property nodes : Array(Node)

    def initialize(@nodes : Array(Node) = [] of Node)
    end
  end

  @[Experimental]
  struct GetFullAXTreeResult
    include JSON::Serializable
    @[JSON::Field(key: "nodes", emit_null: false)]
    property nodes : Array(Node)

    def initialize(@nodes : Array(Node) = [] of Node)
    end
  end

  @[Experimental]
  struct GetRootAXNodeResult
    include JSON::Serializable
    @[JSON::Field(key: "node", emit_null: false)]
    property node : Node?

    def initialize(@node : Node? = nil)
    end
  end

  @[Experimental]
  struct GetAXNodeAndAncestorsResult
    include JSON::Serializable
    @[JSON::Field(key: "nodes", emit_null: false)]
    property nodes : Array(Node)

    def initialize(@nodes : Array(Node) = [] of Node)
    end
  end

  @[Experimental]
  struct GetChildAXNodesResult
    include JSON::Serializable
    @[JSON::Field(key: "nodes", emit_null: false)]
    property nodes : Array(Node)

    def initialize(@nodes : Array(Node) = [] of Node)
    end
  end

  @[Experimental]
  struct QueryAXTreeResult
    include JSON::Serializable
    @[JSON::Field(key: "nodes", emit_null: false)]
    property nodes : Array(Node)

    def initialize(@nodes : Array(Node) = [] of Node)
    end
  end

  # Commands
  struct Disable
    include JSON::Serializable
    include Cdp::Request

    def initialize
    end

    # ProtoReq returns the protocol method name.
    def proto_req : String
      "Accessibility.disable"
    end

    # Call sends the request.
    def call(c : Cdp::Client) : Nil
      Cdp.call(proto_req, self, nil, c)
    end
  end

  struct Enable
    include JSON::Serializable
    include Cdp::Request

    def initialize
    end

    # ProtoReq returns the protocol method name.
    def proto_req : String
      "Accessibility.enable"
    end

    # Call sends the request.
    def call(c : Cdp::Client) : Nil
      Cdp.call(proto_req, self, nil, c)
    end
  end

  @[Experimental]
  struct GetPartialAXTree
    include JSON::Serializable
    include Cdp::Request
    @[JSON::Field(key: "nodeId", emit_null: false)]
    property node_id : Cdp::DOM::NodeId?
    @[JSON::Field(key: "backendNodeId", emit_null: false)]
    property backend_node_id : Cdp::DOM::BackendNodeId?
    @[JSON::Field(key: "objectId", emit_null: false)]
    property object_id : Cdp::Runtime::RemoteObjectId?
    @[JSON::Field(key: "fetchRelatives", emit_null: false)]
    property? fetch_relatives : Bool?

    def initialize(@node_id : Cdp::DOM::NodeId?, @backend_node_id : Cdp::DOM::BackendNodeId?, @object_id : Cdp::Runtime::RemoteObjectId?, @fetch_relatives : Bool?)
    end

    # ProtoReq returns the protocol method name.
    def proto_req : String
      "Accessibility.getPartialAXTree"
    end

    # Call sends the request and returns the result.
    def call(c : Cdp::Client) : GetPartialAXTreeResult
      res = GetPartialAXTreeResult.new
      Cdp.call(proto_req, self, res, c)
      res
    end
  end

  @[Experimental]
  struct GetFullAXTree
    include JSON::Serializable
    include Cdp::Request
    @[JSON::Field(key: "depth", emit_null: false)]
    property depth : Int64?
    @[JSON::Field(key: "frameId", emit_null: false)]
    property frame_id : Cdp::Page::FrameId?

    def initialize(@depth : Int64?, @frame_id : Cdp::Page::FrameId?)
    end

    # ProtoReq returns the protocol method name.
    def proto_req : String
      "Accessibility.getFullAXTree"
    end

    # Call sends the request and returns the result.
    def call(c : Cdp::Client) : GetFullAXTreeResult
      res = GetFullAXTreeResult.new
      Cdp.call(proto_req, self, res, c)
      res
    end
  end

  @[Experimental]
  struct GetRootAXNode
    include JSON::Serializable
    include Cdp::Request
    @[JSON::Field(key: "frameId", emit_null: false)]
    property frame_id : Cdp::Page::FrameId?

    def initialize(@frame_id : Cdp::Page::FrameId?)
    end

    # ProtoReq returns the protocol method name.
    def proto_req : String
      "Accessibility.getRootAXNode"
    end

    # Call sends the request and returns the result.
    def call(c : Cdp::Client) : GetRootAXNodeResult
      res = GetRootAXNodeResult.new
      Cdp.call(proto_req, self, res, c)
      res
    end
  end

  @[Experimental]
  struct GetAXNodeAndAncestors
    include JSON::Serializable
    include Cdp::Request
    @[JSON::Field(key: "nodeId", emit_null: false)]
    property node_id : Cdp::DOM::NodeId?
    @[JSON::Field(key: "backendNodeId", emit_null: false)]
    property backend_node_id : Cdp::DOM::BackendNodeId?
    @[JSON::Field(key: "objectId", emit_null: false)]
    property object_id : Cdp::Runtime::RemoteObjectId?

    def initialize(@node_id : Cdp::DOM::NodeId?, @backend_node_id : Cdp::DOM::BackendNodeId?, @object_id : Cdp::Runtime::RemoteObjectId?)
    end

    # ProtoReq returns the protocol method name.
    def proto_req : String
      "Accessibility.getAXNodeAndAncestors"
    end

    # Call sends the request and returns the result.
    def call(c : Cdp::Client) : GetAXNodeAndAncestorsResult
      res = GetAXNodeAndAncestorsResult.new
      Cdp.call(proto_req, self, res, c)
      res
    end
  end

  @[Experimental]
  struct GetChildAXNodes
    include JSON::Serializable
    include Cdp::Request
    @[JSON::Field(key: "id", emit_null: false)]
    property id : NodeId
    @[JSON::Field(key: "frameId", emit_null: false)]
    property frame_id : Cdp::Page::FrameId?

    def initialize(@id : NodeId, @frame_id : Cdp::Page::FrameId?)
    end

    # ProtoReq returns the protocol method name.
    def proto_req : String
      "Accessibility.getChildAXNodes"
    end

    # Call sends the request and returns the result.
    def call(c : Cdp::Client) : GetChildAXNodesResult
      res = GetChildAXNodesResult.new
      Cdp.call(proto_req, self, res, c)
      res
    end
  end

  @[Experimental]
  struct QueryAXTree
    include JSON::Serializable
    include Cdp::Request
    @[JSON::Field(key: "nodeId", emit_null: false)]
    property node_id : Cdp::DOM::NodeId?
    @[JSON::Field(key: "backendNodeId", emit_null: false)]
    property backend_node_id : Cdp::DOM::BackendNodeId?
    @[JSON::Field(key: "objectId", emit_null: false)]
    property object_id : Cdp::Runtime::RemoteObjectId?
    @[JSON::Field(key: "accessibleName", emit_null: false)]
    property accessible_name : String?
    @[JSON::Field(key: "role", emit_null: false)]
    property role : String?

    def initialize(@node_id : Cdp::DOM::NodeId?, @backend_node_id : Cdp::DOM::BackendNodeId?, @object_id : Cdp::Runtime::RemoteObjectId?, @accessible_name : String?, @role : String?)
    end

    # ProtoReq returns the protocol method name.
    def proto_req : String
      "Accessibility.queryAXTree"
    end

    # Call sends the request and returns the result.
    def call(c : Cdp::Client) : QueryAXTreeResult
      res = QueryAXTreeResult.new
      Cdp.call(proto_req, self, res, c)
      res
    end
  end
end
