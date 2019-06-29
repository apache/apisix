import { Response, Request } from 'express'

const list = <any>[]
for (let i = 0; i <= 50; i++) {
    list.push({
        node: {
            value: {
                upstream: {
                    nodes: {
                        ['127.0.0.1:8080']: 1
                    },
                    type: "roundrobin"
                }
            },
            key: "/apisix/services/1"
        },
        action: "set"
    })
}

export const getServiceList = (req: Request, res: Response) => {
    res.json(list)
}



export const updateService = (req: Request, res: Response) => {
    res.json({
        node: {
            value: {
                upstream: {
                    nodes: {
                        ['127.0.0.1:8080']: 1
                    },
                    type: "roundrobin"
                }
            },
            key: "/apisix/services/1"
        },
        action: "set"
    })
}

export const getService = (req: Request, res: Response) => {
    res.json({
        node: {
            value: {
                upstream: {
                    nodes: {
                        ['127.0.0.1:8080']: 1
                    },
                    type: "roundrobin"
                }
            },
            key: "/apisix/services/1"
        },
        action: "get"
    })
}

export const removeService = (req: Request, res: Response) => {
    res.json({
        action: "delete"
    })
}

export const createService = (req: Request, res: Response) => {
    res.json({
        node: {
            value: {
                upstream: {
                    nodes: {
                        ['127.0.0.1:8080']: 1
                    },
                    type: "roundrobin"
                }
            },
            key: "/apisix/services/1"
        },
        action: "create"
    })
}

