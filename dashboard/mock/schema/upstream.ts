import { Response, Request } from 'express'

const list = <any>[]
for (let i = 0; i <= 50; i++) {
    list.push({
        node: {
            value: {
                nodes: {
                    ['127.0.0.1:8080']: 1
                },
                type: "roundrobin"
            },
            key: "/apisix/upstreams/1"
        },
        action: "get"
    })
}

export const getUpstreamList = (req: Request, res: Response) => {
    res.json(list)
}

export const updateUpstream = (req: Request, res: Response) => {
    res.json({
        node: {
            value: {
                nodes: {
                    ['127.0.0.1:8080']: 1
                },
                type: "roundrobin"
            },
            key: "/apisix/upstreams/1"
        },
        action: "set"
    })
}

export const getUpstream = (req: Request, res: Response) => {
    res.json({
        node: {
            value: {
                nodes: {
                    ['127.0.0.1:8080']: 1
                },
                type: "roundrobin"
            },
            key: "/apisix/upstreams/1"
        },
        action: "get"
    })
}

export const removeUpstream = (req: Request, res: Response) => {
    res.json({
        action: "delete"
    })
}

export const createUpstream = (req: Request, res: Response) => {
    res.json({
        node: {
            value: {
                nodes: {
                    ['127.0.0.1:8080']: 1
                },
                type: "roundrobin"
            }
        },
        action: "create"
    })
}