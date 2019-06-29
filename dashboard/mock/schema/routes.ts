import { Response, Request } from 'express'

const list = <any>[]
for (let i = 0; i <= 50; i++) {
    list.push({
        node: {
            value: {
                methods: [
                    "GET"
                ],
                uri: "/index.html",
                upstream: {
                    nodes: {
                        ['127.0.0.1:8080']: 1
                    },
                    type: "roundrobin"
                }
            },
            key: "/apisix/routes/1"
        },
        action: "get"
    })
}

export const getRoutes = (req: Request, res: Response) => {
  return res.json(list)
}

export const updateRoute = (req: Request, res: Response) => {
    return res.json({
        node: {
            value: {
                methods: [
                    "GET"
                ],
                uri: "/index.html",
                upstream: {
                    nodes: {
                        ['127.0.0.1:8080']: 1
                    },
                    type: "roundrobin"
                }
            },
            key: "/apisix/routes/1"
        },
        action: "set"
    })
}

export const getRoute = (req: Request, res: Response) => {
    return res.json({
        node: {
            value: {
                methods: [
                    "GET"
                ],
                uri: "/index.html",
                upstream: {
                    nodes: {
                        ['127.0.0.1:8080']: 1
                    },
                    type: "roundrobin"
                }
            },
            key: "/apisix/routes/1"
        },
        action: "get"
    })
}

export const removeRoute = (req: Request, res: Response) => {
    return res.status(200)
}

export const createRoute = (req: Request, res: Response) => {
    return res.json({
        node: {
            value: {
                methods: [
                    "GET"
                ],
                uri: "/index.html",
                upstream: {
                    nodes: {
                        ['127.0.0.1:8080']: 1
                    },
                    type: "roundrobin"
                }
            },
            key: "/apisix/routes/1"
        },
        action: "create"
    })
}
