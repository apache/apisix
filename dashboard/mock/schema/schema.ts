import { Response, Request } from 'express'

export const getPluginSchema = (req: Request, res: Response) => {
  const pluginName = req.url.match(/[^\/]*$/)![0]

  let schema = {}

  if (pluginName === 'limit-count') {
    schema = {
      type: 'object',
      properties: {
        count: { type: 'integer', minimum: 0 },
        time_window: { type: 'integer', minimum: 0 },
        key: { type: 'string', enum: ['remote_addr'] },
        rejected_code: { type: 'integer', minimum: 200, maximum: 600 },
      },
      additionalProperties: false,
      required: ['count', 'time_window', 'key', 'rejected_code'],
    }
  }

  if (pluginName === 'key-auth') {
    schema = {
      type: 'object',
      properties: {
        key: { type: 'string' }
      }
    }
  }

  if (pluginName === 'example-plugin') {
    schema = {
      type: 'object',
      properties: {
        i: { type: 'number', minimum: 0 },
        s: { type: 'string' },
        // TODO: 暂未加入针对 array 的逻辑
        t: { type: 'array', minItems: 1 },
      },
      required: ['i']
    }
  }

  if (pluginName === 'limit-conn') {
    schema = {
      type: 'object',
      properties: {
        conn: { type: 'integer', minimum: 0 },
        burst: { type: 'integer', minimum: 0 },
        default_conn_delay: { type: 'number', minimum: 0 },
        key: { type: 'string', enum: ['remote_addr'] },
        rejected_code: { type: 'integer', minimum: 200 },
      },
      required: ['conn', 'burst', 'default_conn_delay', 'key', 'rejected_code']
    }
  }

  if (pluginName === 'limit-req') {
    schema = {
      type: 'object',
      properties: {
        rate: { type: 'number', minimum: 0 },
        burst: { type: 'number', minimum: 0 },
        key: { type: 'string', enum: ['remote_addr'] },
        rejected_code: { type: 'integer', minimum: 200 },
      },
      required: ['rate', 'burst', 'key', 'rejected_code']
    }
  }

  if (pluginName === 'prometheus') {
    schema = {
      type: 'object',
      additionalProperties: false
    }
  }

  return res.json(schema)
}
