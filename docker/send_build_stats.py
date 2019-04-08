import sys
import pprint
import time

from google.cloud import monitoring_v3


def write_time_series(project_id, labels, key, value):
  client = monitoring_v3.MetricServiceClient()
  project_name = client.project_path(project_id)

  series = monitoring_v3.types.TimeSeries()
  series.metric.type = 'custom.googleapis.com/tf_build/' + key
  for k, v in labels.iteritems():
    series.metric.labels[k] = v
  series.resource.type = 'gce_instance'
  series.resource.labels['instance_id'] = '1234567890123456789'
  series.resource.labels['zone'] = 'us-central1-f'
  series.resource.labels['project_id'] = project_id
  point = series.points.add()
  point.value.double_value = value
  now = time.time()
  point.interval.end_time.seconds = int(now)
  point.interval.end_time.nanos = int(
      (now - point.interval.end_time.seconds) * 10**9)
  client.create_time_series(project_name, [series])


def main(argv):
  # Parse the arguments.
  labels = {}
  value = 0.0
  key = ''
  project_id = ''
  for arg in argv:
    if arg.startswith('--'):
      (k, v) = arg.lstrip('-').split('=')
      if k == 'value':
        value = float(v)
      elif k == 'key':
        key = v
      elif k == 'project_id':
        project_id = v
      else:
        labels[k] = v

  write_time_series(project_id, labels, key, value)


if __name__ == '__main__':
  main(sys.argv)
