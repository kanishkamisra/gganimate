#' @importFrom ggplot2 ggproto
create_scene <- function(transition, view, shadow, ease, transmuters, nframes) {
  if (is.null(nframes)) nframes <- 100
  ggproto(NULL, Scene, transition = transition, view = view, shadow = shadow, ease = ease, transmuters = transmuters, nframes = nframes)
}
#' @importFrom ggplot2 ggproto
#' @importFrom glue glue_data
Scene <- ggproto('Scene', NULL,
  transition = NULL,
  view = NULL,
  shadow = NULL,
  ease = NULL,
  transmuters = NULL,
  nframes = integer(),
  transition_params = list(),
  view_params = list(),
  shadow_params = list(),
  layer_type = character(),
  tween_first = logical(),

  setup = function(self, layer_data) {
    transition_params <- self$transition$params
    transition_params$nframes <- self$nframes
    self$transition_params <- self$transition$setup_params(layer_data, transition_params)
    view_params <- self$view$params
    view_params$nframes <- self$nframes
    self$view_params <- self$view$setup_params(layer_data, view_params)
    shadow_params <- self$shadow$params
    shadow_params$nframes <- self$nframes
    self$shadow_params <- self$shadow$setup_params(layer_data, shadow_params)
  },
  identify_layers = function(self, layer_data, layers) {
    self$transmuters$setup(layers)
    self$layer_type = self$get_layer_type(layer_data, layers)
    self$tween_first = self$is_early_tween(layers)
  },
  before_stat = function(self, layer_data) {
    layer_data <- self$transition$map_data(layer_data, self$transition_params)
    ease <- self$ease$get_ease(layer_data[self$tween_first])
    layer_data[self$tween_first] <- self$transition$expand_data(
      layer_data[self$tween_first],
      self$layer_type[self$tween_first],
      ease,
      self$transmuters$enter_transmuters(self$tween_first),
      self$transmuters$exit_transmuters(self$tween_first),
      self$transition_params,
      which(self$tween_first)
    )
    layer_data
  },
  after_stat = function(self, layer_data) {
    layer_data
  },
  before_position = function(self, layer_data) {
    self$transition$unmap_frames(layer_data, self$transition_params)
  },
  after_position = function(self, layer_data) {
    self$transition$remap_frames(layer_data, self$transition_params)
  },
  after_defaults = function(self, layer_data) {
    tween_last <- !self$tween_first
    ease <- self$ease$get_ease(layer_data[tween_last])
    layer_data[tween_last] <- self$transition$expand_data(
      layer_data[tween_last],
      self$layer_type[tween_last],
      ease,
      self$transmuters$enter_transmuters(tween_last),
      self$transmuters$exit_transmuters(tween_last),
      self$transition_params,
      which(tween_last)
    )
    layer_data
  },
  finish_data = function(self, layer_data) {
    layer_data <- self$transition$finish_data(layer_data, self$transition_params)
    self$nframes <- self$transition$adjust_nframes(layer_data, self$transition_params)
    static_layers <- self$transition$static_layers(self$transition_params)
    self$view_params$nframes <- self$nframes
    self$view_params$excluded_layers <- union(self$view$exclude_layer, static_layers)
    self$view_params <- self$view$train(layer_data, self$view_params)
    self$shadow_params$nframes <- self$nframes
    self$shadow_params$excluded_layers <- union(self$shadow$exclude_layer, static_layers)
    self$shadow_params <- self$shadow$train(layer_data, self$shadow_params)
    frame_vars <- list(
      data.frame(frame = seq_len(self$nframes), nframes = self$nframes, progress = seq_len(self$nframes)/self$nframes),
      self$transition$get_frame_vars(self$transition_params),
      self$view$get_frame_vars(self$view_params)
    )
    self$frame_vars <- do.call(cbind, frame_vars[!vapply(frame_vars, is.null, logical(1))])
    layer_data
  },
  get_frame = function(self, plot, i) {
    class(plot) <- 'ggplot_built'
    data <- self$transition$get_frame_data(plot$data, self$transition_params, i)
    shadow_i <- self$shadow$get_frames(self$shadow_params, i)
    shadow <- self$transition$get_frame_data(plot$data, self$transition_params, shadow_i)
    shadow <- self$shadow$prepare_shadow(shadow, self$shadow_params)
    plot$data <- self$shadow$prepare_frame_data(data, shadow, self$shadow_params, i, shadow_i)
    plot <- self$view$set_view(plot, self$view_params, i)
    plot <- self$set_labels(plot, i)
    plot
  },
  set_labels = function(self, plot, i) {
    label_var <- as.list(self$frame_vars[i, ])
    label_var$data <- plot$data
    plot$plot$labels <- lapply(plot$plot$labels, glue_data, .x = label_var, .envir = plot$plot$plot_env)
    plot
  },
  get_layer_type = function(self, data, layers) {
    unlist(Map(function(l, d) {
      layer_type(l$stat) %||% layer_type(l$geom) %||% layer_type(d)
    }, l = layers, d = data))
  },
  is_early_tween = function(self, layers) {
    vapply(layers, tween_before_stat, logical(1))
  }
)
