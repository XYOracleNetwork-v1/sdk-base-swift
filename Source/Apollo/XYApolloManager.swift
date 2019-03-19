//
//  XYApolloManager.swift
//  XyCoreiOS
//
//  Created by Darren Sutherland on 2/4/19.
//  Copyright © 2019 XYO Network. All rights reserved.
//

import Apollo
import Foundation
import Promises

public protocol XYQueryManager: class {
    var cache: ApolloStore { get }

    func fetch<Query: GraphQLQuery>(for query: Query) -> XYApolloFetchRequest<Query>
    func watch<Query: GraphQLQuery>(for query: Query, then callback: @escaping OperationResultHandler<Query>) -> GraphQLQueryWatcher<Query>
    func mutate<Mutation: GraphQLMutation>(for mutation: Mutation) -> XYApolloMutateRequest<Mutation>
}

public enum XYQueryManagerError: Error {
    case timedOut
}

public class XYApolloQueryManager {

    public static let defaultQueue = DispatchQueue(label:"com.xyonetwork.core.sdk.XYApolloQueryManagerOperationsQueue")
    public static let defaultTimeout: DispatchTimeInterval = .seconds(15)

    fileprivate static let timeoutQueue = DispatchQueue(label:"com.xyonetwork.core.sdk.XYApolloQueryManagerTimeoutQueue")

    internal let client: ApolloClient
    internal let queue: DispatchQueue
    internal let timeout: DispatchTimeInterval

    fileprivate static let store = ApolloStore(cache: InMemoryNormalizedCache())

    private static let xyAuthHeader = "X-Auth-Token"
    private static let endpointUrl = "https://cmsltk3yhg.execute-api.us-east-1.amazonaws.com/dev/graphql"

    private static var serverUrl: URL = {
        guard let url = URL(string: endpointUrl) else {
            fatalError("Invalid GraphQL connection URL")
        }
        return url
    }()

    fileprivate init(client: ApolloClient, queue: DispatchQueue, timeout: DispatchTimeInterval) {
        self.client = client
        self.queue = queue
        self.timeout = timeout
    }
}

public extension XYApolloQueryManager {

    public class func nonAuth(
        on queue: DispatchQueue = XYApolloQueryManager.defaultQueue,
        with timeout: DispatchTimeInterval = XYApolloQueryManager.defaultTimeout,
        configuration: URLSessionConfiguration = URLSessionConfiguration.default) -> XYApolloQueryManager {

        let client = ApolloClient(networkTransport: HTTPNetworkTransport(url: serverUrl, configuration: configuration), store: store)
        client.cacheKeyForObject = { $0["id"] }
        return XYApolloQueryManager(client: client, queue: queue, timeout: timeout)
    }

    public class func auth(
        token: String,
        on queue: DispatchQueue = XYApolloQueryManager.defaultQueue,
        with timeout: DispatchTimeInterval = XYApolloQueryManager.defaultTimeout) -> XYApolloQueryManager {

        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = [xyAuthHeader: token]
        return self.nonAuth(on: queue, with: timeout, configuration: configuration)
    }

}

// MARK: Handles the various possible queries
extension XYApolloQueryManager: XYQueryManager {

    public var cache: ApolloStore {
        return XYApolloQueryManager.store
    }

    public func fetch<Query: GraphQLQuery>(for query: Query) -> XYApolloFetchRequest<Query> {
        return XYApolloFetchRequest(query: query, with: self)
    }

    public func watch<Query: GraphQLQuery>(for query: Query, then callback: @escaping OperationResultHandler<Query>) -> GraphQLQueryWatcher<Query> {
        return self.client.watch(query: query, queue: self.queue, resultHandler: callback)
    }

    public func mutate<Mutation: GraphQLMutation>(for mutation: Mutation) -> XYApolloMutateRequest<Mutation> {
        return XYApolloMutateRequest(mutation: mutation, with: self)
    }

}

public protocol XYApolloRequest {
    associatedtype QueryType: GraphQLOperation
    func execute(_ callback: @escaping OperationResultHandler<QueryType>)
}

/// A self contained fetch request, handles timeouts using promises since Apollo returns a handle to cancel
public class XYApolloFetchRequest<Query: GraphQLQuery>: XYApolloRequest {
    public typealias QueryType = Query

    private struct Result {
        let
        data: GraphQLResult<Query.Data>?,
        error: Error?
    }

    private let
    query: Query,
    manager: XYApolloQueryManager

    private var timer: DispatchSourceTimer?
    private var cancelHandle: Cancellable?

    private let workQueue = DispatchQueue(label:"com.xyonetwork.core.sdk.XYApolloFetchRequestQueue")

    internal init(query: Query, with manager: XYApolloQueryManager) {
        self.query = query
        self.manager = manager
    }

    public func execute(_ callback: @escaping OperationResultHandler<Query>) {
        self.workQueue.async {
            do {
                let result = try await(self.execute())
                callback(result.data, result.error)
            } catch {
                callback(nil, error)
            }
        }
    }

    private func execute() -> Promises.Promise<Result> {
        let operationPromise = Promises.Promise<Result>.pending()

        self.cancelHandle = self.manager.client.fetch(query: self.query, queue: self.manager.queue) { [weak self] result, error in
            self?.timer = nil
            operationPromise.fulfill(Result(data: result, error: error))
        }

        self.timer = DispatchSource.singleTimer(interval: self.manager.timeout, queue: XYApolloQueryManager.timeoutQueue) { [weak self] in
            self?.cancelHandle?.cancel()
            operationPromise.reject(XYQueryManagerError.timedOut)
        }

        return operationPromise
    }

}

/// A self contained mutate request, handles timeouts using promises since Apollo returns a handle to cancel
public class XYApolloMutateRequest<Mutation: GraphQLMutation>: XYApolloRequest {
    public typealias QueryType = Mutation

    private struct Result {
        let
        data: GraphQLResult<Mutation.Data>?,
        error: Error?
    }

    private let
    mutation: Mutation,
    manager: XYApolloQueryManager

    private var timer: DispatchSourceTimer?
    private var cancelHandle: Cancellable?

    private let workQueue = DispatchQueue(label:"com.xyonetwork.core.sdk.XYApolloMutateRequestQueue")

    internal init(mutation: Mutation, with manager: XYApolloQueryManager) {
        self.mutation = mutation
        self.manager = manager
    }

    public func execute(_ callback: @escaping OperationResultHandler<Mutation>) {
        self.workQueue.async {
            do {
                let result = try await(self.execute())
                callback(result.data, result.error)
            } catch {
                callback(nil, error)
            }
        }
    }

    private func execute() -> Promises.Promise<Result> {
        let operationPromise = Promises.Promise<Result>.pending()

        self.cancelHandle = self.manager.client.perform(mutation: self.mutation, queue: self.manager.queue) { [weak self] result, error in
            self?.timer = nil
            operationPromise.fulfill(Result(data: result, error: error))
        }

        self.timer = DispatchSource.singleTimer(interval: self.manager.timeout, queue: XYApolloQueryManager.timeoutQueue) { [weak self] in
            self?.cancelHandle?.cancel()
            operationPromise.reject(XYQueryManagerError.timedOut)
        }

        return operationPromise
    }

}
